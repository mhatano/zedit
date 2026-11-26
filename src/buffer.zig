const std = @import("std");

pub const LineCol = struct {
    line: usize,
    col: usize, // byte offset within line
};

pub const Range = struct {
    start: usize,
    end: usize,
};

pub const LineRange = struct {
    start: usize,
    end: usize, // excluding '\n'
    end_with_nl: usize,
};

pub const EditKind = enum {
    insert,
    delete,
};

pub const EditOp = struct {
    kind: EditKind,
    offset: usize,
    text: []u8,
    cursor_before: usize,
    cursor_after: usize,
    group_id: u64,
};

pub const TextBuffer = struct {
    allocator: std.mem.Allocator,
    data: []u8,
    gap_start: usize,
    gap_end: usize,

    line_starts: std.ArrayList(usize),
    lines_dirty: bool,

    undo_stack: std.ArrayList(EditOp),
    redo_stack: std.ArrayList(EditOp),
    next_group_id: u64,
    active_group_id: ?u64,
    last_edit_time_ms: i64,

    saved_undo_len: ?usize,
    crlf: bool,
    path: ?[]u8,
    untitled_id: usize,

    // View & selection state per tab/buffer
    cursor: usize,
    anchor: ?usize, // non-null when selection is active
    preferred_col: ?usize, // visual column for vertical navigation
    scroll_row: usize,
    scroll_col: usize,

    const INITIAL_GAP: usize = 256;
    const COALESCE_WINDOW_MS: i64 = 600;

    pub fn init(allocator: std.mem.Allocator, untitled_id: usize) !TextBuffer {
        const data = try allocator.alloc(u8, INITIAL_GAP);
        var line_starts = std.ArrayList(usize).init(allocator);
        try line_starts.append(0);
        return TextBuffer{
            .allocator = allocator,
            .data = data,
            .gap_start = 0,
            .gap_end = INITIAL_GAP,
            .line_starts = line_starts,
            .lines_dirty = false,
            .undo_stack = std.ArrayList(EditOp).init(allocator),
            .redo_stack = std.ArrayList(EditOp).init(allocator),
            .next_group_id = 1,
            .active_group_id = null,
            .last_edit_time_ms = 0,
            .saved_undo_len = 0,
            .crlf = false,
            .path = null,
            .untitled_id = untitled_id,
            .cursor = 0,
            .anchor = null,
            .preferred_col = null,
            .scroll_row = 0,
            .scroll_col = 0,
        };
    }

    pub fn deinit(self: *TextBuffer) void {
        self.allocator.free(self.data);
        self.line_starts.deinit();
        for (self.undo_stack.items) |op| self.allocator.free(op.text);
        self.undo_stack.deinit();
        for (self.redo_stack.items) |op| self.allocator.free(op.text);
        self.redo_stack.deinit();
        if (self.path) |p| self.allocator.free(p);
    }

    pub fn loadFile(allocator: std.mem.Allocator, file_path: []const u8) !TextBuffer {
        var buf = try TextBuffer.init(allocator, 0);
        errdefer buf.deinit();

        buf.path = try allocator.dupe(u8, file_path);

        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Allow opening a new file path directly
                return buf;
            }
            return err;
        };
        defer file.close();

        const raw = try file.readToEndAlloc(allocator, 128 * 1024 * 1024);
        defer allocator.free(raw);

        // Detect CRLF and normalize to LF in memory
        var has_crlf = false;
        var norm = std.ArrayList(u8).init(allocator);
        defer norm.deinit();
        try norm.ensureTotalCapacity(raw.len);

        var i: usize = 0;
        while (i < raw.len) : (i += 1) {
            if (raw[i] == '\r' and i + 1 < raw.len and raw[i + 1] == '\n') {
                has_crlf = true;
                continue;
            }
            try norm.append(raw[i]);
        }

        buf.crlf = has_crlf;
        try buf.insertRaw(0, norm.items);
        buf.saved_undo_len = 0;
        buf.cursor = 0;
        buf.ensureLineIndex();
        return buf;
    }

    pub fn save(self: *TextBuffer) !void {
        const file_path = self.path orelse return error.NoFilePath;
        const file = try std.fs.cwd().createFile(file_path, .{ .truncate = true });
        defer file.close();

        var buffered = std.io.bufferedWriter(file.writer());
        const w = buffered.writer();

        if (!self.crlf) {
            try w.writeAll(self.data[0..self.gap_start]);
            try w.writeAll(self.data[self.gap_end..self.data.len]);
        } else {
            try writeWithCrlf(w, self.data[0..self.gap_start]);
            try writeWithCrlf(w, self.data[self.gap_end..self.data.len]);
        }
        try buffered.flush();
        self.saved_undo_len = self.undo_stack.items.len;
    }

    fn writeWithCrlf(writer: anytype, slice: []const u8) !void {
        var start: usize = 0;
        while (std.mem.indexOfScalarPos(u8, slice, start, '\n')) |nl| {
            try writer.writeAll(slice[start..nl]);
            try writer.writeAll("\r\n");
            start = nl + 1;
        }
        if (start < slice.len) {
            try writer.writeAll(slice[start..]);
        }
    }

    pub fn setPath(self: *TextBuffer, new_path: []const u8) !void {
        const duped = try self.allocator.dupe(u8, new_path);
        if (self.path) |old| self.allocator.free(old);
        self.path = duped;
    }

    pub fn displayName(self: *const TextBuffer) []const u8 {
        if (self.path) |p| {
            return std.fs.path.basename(p);
        }
        return "untitled";
    }

    pub fn isModified(self: *const TextBuffer) bool {
        if (self.saved_undo_len) |saved| {
            return saved != self.undo_stack.items.len;
        }
        return true;
    }

    pub inline fn len(self: *const TextBuffer) usize {
        return self.data.len - (self.gap_end - self.gap_start);
    }

    pub inline fn byteAt(self: *const TextBuffer, idx: usize) u8 {
        if (idx < self.gap_start) {
            return self.data[idx];
        }
        return self.data[idx + (self.gap_end - self.gap_start)];
    }

    fn moveGap(self: *TextBuffer, pos: usize) void {
        const target = @min(pos, self.len());
        if (target == self.gap_start) return;

        if (target < self.gap_start) {
            const count = self.gap_start - target;
            const new_gap_end = self.gap_end - count;
            std.mem.copyBackwards(u8, self.data[new_gap_end..self.gap_end], self.data[target..self.gap_start]);
            self.gap_start = target;
            self.gap_end = new_gap_end;
        } else {
            const count = target - self.gap_start;
            std.mem.copyForwards(u8, self.data[self.gap_start .. self.gap_start + count], self.data[self.gap_end .. self.gap_end + count]);
            self.gap_start += count;
            self.gap_end += count;
        }
    }

    fn ensureGap(self: *TextBuffer, needed: usize) !void {
        const gap_len = self.gap_end - self.gap_start;
        if (gap_len >= needed) return;

        const text_len = self.len();
        const after_len = self.data.len - self.gap_end;
        const new_cap = @max(self.data.len * 2, text_len + needed + INITIAL_GAP);

        const new_data = try self.allocator.alloc(u8, new_cap);
        @memcpy(new_data[0..self.gap_start], self.data[0..self.gap_start]);
        const new_gap_end = new_cap - after_len;
        @memcpy(new_data[new_gap_end..new_cap], self.data[self.gap_end..self.data.len]);

        self.allocator.free(self.data);
        self.data = new_data;
        self.gap_end = new_gap_end;
    }

    pub fn insertRaw(self: *TextBuffer, pos: usize, bytes: []const u8) !void {
        if (bytes.len == 0) return;
        const clamped = @min(pos, self.len());
        self.moveGap(clamped);
        try self.ensureGap(bytes.len);
        @memcpy(self.data[self.gap_start .. self.gap_start + bytes.len], bytes);
        self.gap_start += bytes.len;
        self.lines_dirty = true;
    }

    pub fn deleteRaw(self: *TextBuffer, pos: usize, count: usize) void {
        if (count == 0 or pos >= self.len()) return;
        const actual = @min(count, self.len() - pos);
        self.moveGap(pos);
        self.gap_end += actual;
        self.lines_dirty = true;
    }

    pub fn copyRange(self: *const TextBuffer, start: usize, count: usize, out: []u8) usize {
        const text_len = self.len();
        if (start >= text_len or count == 0) return 0;
        const actual = @min(count, text_len - start);
        const end = start + actual;

        if (end <= self.gap_start) {
            @memcpy(out[0..actual], self.data[start..end]);
        } else if (start >= self.gap_start) {
            const gap_len = self.gap_end - self.gap_start;
            @memcpy(out[0..actual], self.data[start + gap_len .. end + gap_len]);
        } else {
            const first = self.gap_start - start;
            const second = actual - first;
            @memcpy(out[0..first], self.data[start..self.gap_start]);
            @memcpy(out[first..actual], self.data[self.gap_end .. self.gap_end + second]);
        }
        return actual;
    }

    pub fn copyRangeAlloc(self: *const TextBuffer, allocator: std.mem.Allocator, start: usize, count: usize) ![]u8 {
        const text_len = self.len();
        const clamped_start = @min(start, text_len);
        const actual = @min(count, text_len - clamped_start);
        const out = try allocator.alloc(u8, actual);
        _ = self.copyRange(clamped_start, actual, out);
        return out;
    }

    pub fn toOwnedSlice(self: *const TextBuffer, allocator: std.mem.Allocator) ![]u8 {
        return self.copyRangeAlloc(allocator, 0, self.len());
    }

    // --- Undo / Redo ---

    pub fn beginGroup(self: *TextBuffer) void {
        if (self.active_group_id == null) {
            self.active_group_id = self.next_group_id;
            self.next_group_id += 1;
        }
    }

    pub fn endGroup(self: *TextBuffer) void {
        self.active_group_id = null;
    }

    fn clearRedo(self: *TextBuffer) void {
        for (self.redo_stack.items) |op| self.allocator.free(op.text);
        self.redo_stack.clearRetainingCapacity();
    }

    pub fn insert(self: *TextBuffer, pos: usize, bytes: []const u8) !void {
        if (bytes.len == 0) return;
        const clamped = @min(pos, self.len());
        const cursor_before = self.cursor;
        try self.insertRaw(clamped, bytes);
        self.cursor = clamped + bytes.len;
        self.clearRedo();

        if (self.saved_undo_len) |saved| {
            if (saved > self.undo_stack.items.len) {
                self.saved_undo_len = null;
            }
        }

        const now = std.time.milliTimestamp();
        const can_coalesce = self.active_group_id == null and
            bytes.len == 1 and bytes[0] != '\n' and
            self.undo_stack.items.len > 0 and
            (now - self.last_edit_time_ms) <= COALESCE_WINDOW_MS and
            (self.saved_undo_len == null or self.saved_undo_len.? != self.undo_stack.items.len);

        if (can_coalesce) {
            const last = &self.undo_stack.items[self.undo_stack.items.len - 1];
            if (last.kind == .insert and last.offset + last.text.len == clamped and
                last.text.len < 64 and !isWordBreakBoundary(last.text[last.text.len - 1], bytes[0]))
            {
                const merged = try self.allocator.alloc(u8, last.text.len + bytes.len);
                @memcpy(merged[0..last.text.len], last.text);
                @memcpy(merged[last.text.len..], bytes);
                self.allocator.free(last.text);
                last.text = merged;
                last.cursor_after = self.cursor;
                self.last_edit_time_ms = now;
                return;
            }
        }

        const group_id = self.active_group_id orelse blk: {
            const id = self.next_group_id;
            self.next_group_id += 1;
            break :blk id;
        };

        const text_copy = try self.allocator.dupe(u8, bytes);
        errdefer self.allocator.free(text_copy);
        try self.undo_stack.append(.{
            .kind = .insert,
            .offset = clamped,
            .text = text_copy,
            .cursor_before = cursor_before,
            .cursor_after = self.cursor,
            .group_id = group_id,
        });
        self.last_edit_time_ms = now;
    }

    pub fn delete(self: *TextBuffer, pos: usize, count: usize) !void {
        if (count == 0 or pos >= self.len()) return;
        const actual = @min(count, self.len() - pos);
        const cursor_before = self.cursor;
        const deleted = try self.copyRangeAlloc(self.allocator, pos, actual);
        errdefer self.allocator.free(deleted);

        self.deleteRaw(pos, actual);
        self.cursor = pos;
        self.clearRedo();

        if (self.saved_undo_len) |saved| {
            if (saved > self.undo_stack.items.len) {
                self.saved_undo_len = null;
            }
        }

        const group_id = self.active_group_id orelse blk: {
            const id = self.next_group_id;
            self.next_group_id += 1;
            break :blk id;
        };

        try self.undo_stack.append(.{
            .kind = .delete,
            .offset = pos,
            .text = deleted,
            .cursor_before = cursor_before,
            .cursor_after = pos,
            .group_id = group_id,
        });
        self.last_edit_time_ms = std.time.milliTimestamp();
    }

    fn isWordBreakBoundary(prev: u8, next: u8) bool {
        return (prev == ' ' or prev == '\t') and (next != ' ' and next != '\t');
    }

    pub fn undo(self: *TextBuffer) !bool {
        if (self.undo_stack.items.len == 0) return false;
        self.anchor = null;
        const target_group = self.undo_stack.items[self.undo_stack.items.len - 1].group_id;

        while (self.undo_stack.items.len > 0) {
            const top = self.undo_stack.items[self.undo_stack.items.len - 1];
            if (top.group_id != target_group) break;
            const op = self.undo_stack.pop().?;

            switch (op.kind) {
                .insert => {
                    self.deleteRaw(op.offset, op.text.len);
                },
                .delete => {
                    try self.insertRaw(op.offset, op.text);
                },
            }
            self.cursor = op.cursor_before;
            try self.redo_stack.append(op);
        }
        return true;
    }

    pub fn redo(self: *TextBuffer) !bool {
        if (self.redo_stack.items.len == 0) return false;
        self.anchor = null;
        const target_group = self.redo_stack.items[self.redo_stack.items.len - 1].group_id;

        while (self.redo_stack.items.len > 0) {
            const top = self.redo_stack.items[self.redo_stack.items.len - 1];
            if (top.group_id != target_group) break;
            const op = self.redo_stack.pop().?;

            switch (op.kind) {
                .insert => {
                    try self.insertRaw(op.offset, op.text);
                },
                .delete => {
                    self.deleteRaw(op.offset, op.text.len);
                },
            }
            self.cursor = op.cursor_after;
            try self.undo_stack.append(op);
        }
        return true;
    }

    // --- Line Index ---

    pub fn ensureLineIndex(self: *TextBuffer) void {
        if (!self.lines_dirty) return;
        self.line_starts.clearRetainingCapacity();
        self.line_starts.append(0) catch return;

        // Scan before gap
        const before = self.data[0..self.gap_start];
        var pos: usize = 0;
        while (std.mem.indexOfScalarPos(u8, before, pos, '\n')) |nl| {
            self.line_starts.append(nl + 1) catch return;
            pos = nl + 1;
        }

        // Scan after gap
        const after = self.data[self.gap_end..self.data.len];
        const base = self.gap_start;
        pos = 0;
        while (std.mem.indexOfScalarPos(u8, after, pos, '\n')) |nl| {
            self.line_starts.append(base + nl + 1) catch return;
            pos = nl + 1;
        }

        self.lines_dirty = false;
    }

    pub fn lineCount(self: *TextBuffer) usize {
        self.ensureLineIndex();
        return self.line_starts.items.len;
    }

    pub fn lineRange(self: *TextBuffer, row: usize) LineRange {
        self.ensureLineIndex();
        const starts = self.line_starts.items;
        const clamped_row = @min(row, starts.len - 1);
        const start = starts[clamped_row];
        const end_with_nl = if (clamped_row + 1 < starts.len) starts[clamped_row + 1] else self.len();
        var end = end_with_nl;
        if (end > start and self.byteAt(end - 1) == '\n') {
            end -= 1;
        }
        return .{
            .start = start,
            .end = end,
            .end_with_nl = end_with_nl,
        };
    }

    pub fn readLine(self: *TextBuffer, row: usize, out: *std.ArrayList(u8)) ![]const u8 {
        out.clearRetainingCapacity();
        const r = self.lineRange(row);
        const line_len = r.end - r.start;
        try out.resize(line_len);
        _ = self.copyRange(r.start, line_len, out.items);
        return out.items;
    }

    pub fn offsetToLineCol(self: *TextBuffer, offset: usize) LineCol {
        self.ensureLineIndex();
        const starts = self.line_starts.items;
        const clamped = @min(offset, self.len());

        // Binary search for largest starts[mid] <= clamped
        var lo: usize = 0;
        var hi: usize = starts.len;
        while (lo + 1 < hi) {
            const mid = lo + (hi - lo) / 2;
            if (starts[mid] <= clamped) {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        return .{
            .line = lo,
            .col = clamped - starts[lo],
        };
    }

    pub fn lineColToOffset(self: *TextBuffer, line: usize, col: usize) usize {
        const r = self.lineRange(line);
        const line_len = r.end - r.start;
        return r.start + @min(col, line_len);
    }

    // --- Selection Helpers ---

    pub fn selectionRange(self: *const TextBuffer) ?Range {
        const a = self.anchor orelse return null;
        if (a == self.cursor) return null;
        return if (a < self.cursor)
            .{ .start = a, .end = self.cursor }
        else
            .{ .start = self.cursor, .end = a };
    }

    pub fn deleteSelection(self: *TextBuffer) !bool {
        const sel = self.selectionRange() orelse {
            self.anchor = null;
            return false;
        };
        self.anchor = null;
        try self.delete(sel.start, sel.end - sel.start);
        return true;
    }

    // --- UTF-8 & Word Motion Helpers ---

    pub fn prevCharOffset(self: *const TextBuffer, offset: usize) usize {
        if (offset == 0) return 0;
        var pos = @min(offset, self.len()) - 1;
        while (pos > 0 and (self.byteAt(pos) & 0xC0) == 0x80) {
            pos -= 1;
        }
        return pos;
    }

    pub fn nextCharOffset(self: *const TextBuffer, offset: usize) usize {
        const total = self.len();
        if (offset >= total) return total;
        const b = self.byteAt(offset);
        const seq_len = std.unicode.utf8ByteSequenceLength(b) catch 1;
        return @min(total, offset + seq_len);
    }

    pub fn isWordByte(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_' or c >= 0x80;
    }

    pub fn prevWordOffset(self: *const TextBuffer, offset: usize) usize {
        var pos = @min(offset, self.len());
        if (pos == 0) return 0;
        // Skip whitespace / non-newline punctuation
        while (pos > 0 and (self.byteAt(pos - 1) == ' ' or self.byteAt(pos - 1) == '\t')) {
            pos -= 1;
        }
        if (pos == 0) return 0;
        if (self.byteAt(pos - 1) == '\n') {
            return pos - 1;
        }
        if (isWordByte(self.byteAt(pos - 1))) {
            while (pos > 0 and isWordByte(self.byteAt(pos - 1))) {
                pos -= 1;
            }
        } else {
            while (pos > 0 and !isWordByte(self.byteAt(pos - 1)) and self.byteAt(pos - 1) != ' ' and self.byteAt(pos - 1) != '\t' and self.byteAt(pos - 1) != '\n') {
                pos -= 1;
            }
        }
        return pos;
    }

    pub fn nextWordOffset(self: *const TextBuffer, offset: usize) usize {
        const total = self.len();
        var pos = @min(offset, total);
        if (pos >= total) return total;
        if (self.byteAt(pos) == '\n') return pos + 1;

        if (isWordByte(self.byteAt(pos))) {
            while (pos < total and isWordByte(self.byteAt(pos))) pos += 1;
        } else if (self.byteAt(pos) != ' ' and self.byteAt(pos) != '\t') {
            while (pos < total and !isWordByte(self.byteAt(pos)) and self.byteAt(pos) != ' ' and self.byteAt(pos) != '\t' and self.byteAt(pos) != '\n') pos += 1;
        }
        while (pos < total and (self.byteAt(pos) == ' ' or self.byteAt(pos) == '\t')) pos += 1;
        return pos;
    }
};

test "TextBuffer gap operations, line indexing, and undo/redo" {
    const alloc = std.testing.allocator;
    var buf = try TextBuffer.init(alloc, 1);
    defer buf.deinit();

    try buf.insert(0, "hello\nworld");
    try std.testing.expectEqual(@as(usize, 11), buf.len());
    try std.testing.expectEqual(@as(usize, 2), buf.lineCount());

    const lc = buf.offsetToLineCol(8);
    try std.testing.expectEqual(@as(usize, 1), lc.line);
    try std.testing.expectEqual(@as(usize, 2), lc.col);

    try buf.insert(5, " zig");
    const full1 = try buf.toOwnedSlice(alloc);
    defer alloc.free(full1);
    try std.testing.expectEqualStrings("hello zig\nworld", full1);
    try std.testing.expect(buf.isModified());

    try buf.delete(5, 4);
    const full2 = try buf.toOwnedSlice(alloc);
    defer alloc.free(full2);
    try std.testing.expectEqualStrings("hello\nworld", full2);

    try std.testing.expect(try buf.undo());
    const full3 = try buf.toOwnedSlice(alloc);
    defer alloc.free(full3);
    try std.testing.expectEqualStrings("hello zig\nworld", full3);

    try std.testing.expect(try buf.redo());
    const full4 = try buf.toOwnedSlice(alloc);
    defer alloc.free(full4);
    try std.testing.expectEqualStrings("hello\nworld", full4);
}
