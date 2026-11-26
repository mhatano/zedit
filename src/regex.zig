const std = @import("std");

pub const Match = struct {
    start: usize,
    end: usize,
};

pub const CharClass = struct {
    bits: [4]u64 = .{ 0, 0, 0, 0 },

    pub fn set(self: *CharClass, b: u8) void {
        self.bits[b >> 6] |= (@as(u64, 1) << @as(u6, @truncate(b & 63)));
    }

    pub fn setRange(self: *CharClass, lo: u8, hi: u8) void {
        var c: usize = lo;
        while (c <= hi) : (c += 1) {
            self.set(@as(u8, @intCast(c)));
        }
    }

    pub fn contains(self: *const CharClass, b: u8) bool {
        return (self.bits[b >> 6] & (@as(u64, 1) << @as(u6, @truncate(b & 63)))) != 0;
    }

    pub fn invert(self: *CharClass) void {
        for (&self.bits) |*w| w.* = ~w.*;
    }

    pub fn merge(self: *CharClass, other: CharClass) void {
        for (&self.bits, other.bits) |*w, o| w.* |= o;
    }

    pub fn addCaseInsensitive(self: *CharClass) void {
        var c: u8 = 'a';
        while (c <= 'z') : (c += 1) {
            const upper = c - 32;
            if (self.contains(c) or self.contains(upper)) {
                self.set(c);
                self.set(upper);
            }
        }
    }
};

const Inst = union(enum) {
    char: u8,
    any,
    class: u16,
    anchor_start,
    anchor_end,
    word_boundary,
    non_word_boundary,
    jmp: u32,
    split: struct { a: u32, b: u32 },
    match,
};

pub const CompileError = error{
    UnexpectedEnd,
    UnmatchedParen,
    InvalidClass,
    InvalidQuantifier,
    TooComplex,
    OutOfMemory,
};

pub const Regex = struct {
    allocator: std.mem.Allocator,
    insts: []Inst,
    classes: []CharClass,
    case_insensitive: bool,

    pub fn compile(allocator: std.mem.Allocator, pattern: []const u8, case_insensitive: bool) CompileError!Regex {
        var compiler = Compiler{
            .allocator = allocator,
            .pattern = pattern,
            .pos = 0,
            .case_insensitive = case_insensitive,
            .insts = std.ArrayList(Inst).init(allocator),
            .classes = std.ArrayList(CharClass).init(allocator),
        };
        errdefer {
            compiler.insts.deinit();
            compiler.classes.deinit();
        }

        try compiler.parseAlt();
        if (compiler.pos != pattern.len) {
            return error.UnmatchedParen;
        }
        try compiler.insts.append(.match);

        return Regex{
            .allocator = allocator,
            .insts = try compiler.insts.toOwnedSlice(),
            .classes = try compiler.classes.toOwnedSlice(),
            .case_insensitive = case_insensitive,
        };
    }

    pub fn deinit(self: *Regex) void {
        self.allocator.free(self.insts);
        self.allocator.free(self.classes);
    }

    const Thread = struct {
        pc: u32,
        start: usize,
    };

    pub fn findNext(self: *const Regex, allocator: std.mem.Allocator, text: []const u8, start_pos: usize) !?Match {
        if (start_pos > text.len) return null;

        const n = self.insts.len;
        var curr = std.ArrayList(Thread).init(allocator);
        defer curr.deinit();
        var next = std.ArrayList(Thread).init(allocator);
        defer next.deinit();

        const visited = try allocator.alloc(u32, n);
        defer allocator.free(visited);
        @memset(visited, 0);
        var gen: u32 = 1;

        var best: ?Match = null;
        var i: usize = start_pos;

        while (true) {
            // Spawn a new thread starting at position i if we haven't found a match yet
            if (best == null) {
                try self.addThread(&curr, visited, gen, 0, i, text, i);
            }

            if (curr.items.len == 0) {
                if (best != null or i >= text.len) break;
                i += 1;
                gen +%= 1;
                if (gen == 0) {
                    @memset(visited, 0);
                    gen = 1;
                }
                continue;
            }

            next.clearRetainingCapacity();
            gen +%= 1;
            if (gen == 0) {
                @memset(visited, 0);
                gen = 1;
            }

            var matched_this_step = false;
            for (curr.items) |t| {
                const inst = self.insts[t.pc];
                switch (inst) {
                    .match => {
                        if (best == null or t.start < best.?.start or (t.start == best.?.start and i >= best.?.end)) {
                            best = .{ .start = t.start, .end = i };
                        }
                        matched_this_step = true;
                        break; // Leftmost-first: drop lower-priority threads
                    },
                    .char => |c| {
                        if (i < text.len and self.matchChar(text[i], c)) {
                            try self.addThread(&next, visited, gen, t.pc + 1, t.start, text, i + 1);
                        }
                    },
                    .any => {
                        if (i < text.len and text[i] != '\n') {
                            try self.addThread(&next, visited, gen, t.pc + 1, t.start, text, i + 1);
                        }
                    },
                    .class => |cid| {
                        if (i < text.len and self.classes[cid].contains(text[i])) {
                            try self.addThread(&next, visited, gen, t.pc + 1, t.start, text, i + 1);
                        }
                    },
                    else => {},
                }
            }

            // Swap curr and next
            const tmp = curr;
            curr = next;
            next = tmp;
            next.clearRetainingCapacity();

            if (i >= text.len) {
                // One final check for zero-width matches at EOF inside curr
                for (curr.items) |t| {
                    if (self.insts[t.pc] == .match) {
                        if (best == null or t.start < best.?.start or (t.start == best.?.start and i >= best.?.end)) {
                            best = .{ .start = t.start, .end = i };
                        }
                        break;
                    }
                }
                break;
            }

            if (matched_this_step and curr.items.len == 0) break;
            i += 1;
        }

        return best;
    }

    pub fn findAll(self: *const Regex, allocator: std.mem.Allocator, text: []const u8, max_matches: usize) !std.ArrayList(Match) {
        var matches = std.ArrayList(Match).init(allocator);
        errdefer matches.deinit();

        var pos: usize = 0;
        while (pos <= text.len and matches.items.len < max_matches) {
            const m = try self.findNext(allocator, text, pos) orelse break;
            try matches.append(m);
            if (m.end > m.start) {
                pos = m.end;
            } else {
                // Zero-width match: advance by 1 byte to avoid infinite loop
                if (pos >= text.len) break;
                pos = m.end + 1;
            }
        }
        return matches;
    }

    inline fn matchChar(self: *const Regex, a: u8, b: u8) bool {
        if (!self.case_insensitive) return a == b;
        return std.ascii.toLower(a) == std.ascii.toLower(b);
    }

    fn isWordChar(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_';
    }

    fn isAtWordBoundary(text: []const u8, pos: usize) bool {
        const left = if (pos > 0) isWordChar(text[pos - 1]) else false;
        const right = if (pos < text.len) isWordChar(text[pos]) else false;
        return left != right;
    }

    fn addThread(
        self: *const Regex,
        list: *std.ArrayList(Thread),
        visited: []u32,
        gen: u32,
        pc: u32,
        start: usize,
        text: []const u8,
        pos: usize,
    ) !void {
        // Explicit stack for epsilon closure to prevent deep recursion
        var stack_buf: [256]u32 = undefined;
        var sp: usize = 0;
        stack_buf[sp] = pc;
        sp += 1;

        while (sp > 0) {
            sp -= 1;
            const cur_pc = stack_buf[sp];
            if (visited[cur_pc] == gen) continue;
            visited[cur_pc] = gen;

            switch (self.insts[cur_pc]) {
                .jmp => |target| {
                    if (sp < stack_buf.len) {
                        stack_buf[sp] = target;
                        sp += 1;
                    }
                },
                .split => |s| {
                    // Push b first so a is popped first (preserves priority order!)
                    if (sp + 2 <= stack_buf.len) {
                        stack_buf[sp] = s.b;
                        stack_buf[sp + 1] = s.a;
                        sp += 2;
                    }
                },
                .anchor_start => {
                    if (pos == 0 or text[pos - 1] == '\n') {
                        if (sp < stack_buf.len) {
                            stack_buf[sp] = cur_pc + 1;
                            sp += 1;
                        }
                    }
                },
                .anchor_end => {
                    if (pos == text.len or text[pos] == '\n') {
                        if (sp < stack_buf.len) {
                            stack_buf[sp] = cur_pc + 1;
                            sp += 1;
                        }
                    }
                },
                .word_boundary => {
                    if (isAtWordBoundary(text, pos)) {
                        if (sp < stack_buf.len) {
                            stack_buf[sp] = cur_pc + 1;
                            sp += 1;
                        }
                    }
                },
                .non_word_boundary => {
                    if (!isAtWordBoundary(text, pos)) {
                        if (sp < stack_buf.len) {
                            stack_buf[sp] = cur_pc + 1;
                            sp += 1;
                        }
                    }
                },
                else => {
                    try list.append(.{ .pc = cur_pc, .start = start });
                },
            }
        }
    }
};

const Compiler = struct {
    allocator: std.mem.Allocator,
    pattern: []const u8,
    pos: usize,
    case_insensitive: bool,
    insts: std.ArrayList(Inst),
    classes: std.ArrayList(CharClass),

    const MAX_INSTS: usize = 4096;

    fn peek(self: *const Compiler) ?u8 {
        if (self.pos >= self.pattern.len) return null;
        return self.pattern[self.pos];
    }

    fn parseAlt(self: *Compiler) CompileError!void {
        var branch_starts = std.ArrayList(usize).init(self.allocator);
        defer branch_starts.deinit();

        // Parse first branch into a temporary list or patch splits cleanly
        const start_idx = self.insts.items.len;
        try self.parseConcat();

        if (self.peek() != '|') return;

        // Collect all branches as separate slices then combine with splits + jmps
        var branches = std.ArrayList([]Inst).init(self.allocator);
        defer {
            for (branches.items) |b| self.allocator.free(b);
            branches.deinit();
        }

        // Extract first branch (rebasing offsets relative to 0)
        const first = try self.extractBranch(start_idx);
        try branches.append(first);

        while (self.peek() == '|') {
            self.pos += 1;
            const b_start = self.insts.items.len;
            try self.parseConcat();
            const b_slice = try self.extractBranch(b_start);
            try branches.append(b_slice);
        }

        // Emit chain of splits and jumps
        // For N branches:
        // split(b0, next_split) -> b0 -> jmp(end)
        // split(b1, next_split) -> b1 -> jmp(end)
        // ...
        // b_{N-1}
        var end_jmps = std.ArrayList(usize).init(self.allocator);
        defer end_jmps.deinit();

        for (branches.items, 0..) |branch, bi| {
            const is_last = (bi + 1 == branches.items.len);
            var split_idx: usize = 0;
            if (!is_last) {
                split_idx = self.insts.items.len;
                try self.insts.append(.{ .split = .{ .a = 0, .b = 0 } });
            }

            const body_base: u32 = @intCast(self.insts.items.len);
            try self.appendRelocated(branch, body_base);

            if (!is_last) {
                const jmp_idx = self.insts.items.len;
                try self.insts.append(.{ .jmp = 0 });
                try end_jmps.append(jmp_idx);
                const next_branch_pc: u32 = @intCast(self.insts.items.len);
                self.insts.items[split_idx] = .{ .split = .{ .a = body_base, .b = next_branch_pc } };
            }
        }

        const end_pc: u32 = @intCast(self.insts.items.len);
        for (end_jmps.items) |jidx| {
            self.insts.items[jidx] = .{ .jmp = end_pc };
        }
    }

    fn extractBranch(self: *Compiler, start_idx: usize) CompileError![]Inst {
        const count = self.insts.items.len - start_idx;
        const slice = try self.allocator.alloc(Inst, count);
        const base: u32 = @intCast(start_idx);
        for (self.insts.items[start_idx..], 0..) |inst, idx| {
            slice[idx] = rebaseInst(inst, base, 0);
        }
        self.insts.shrinkRetainingCapacity(start_idx);
        return slice;
    }

    fn appendRelocated(self: *Compiler, slice: []const Inst, new_base: u32) CompileError!void {
        if (self.insts.items.len + slice.len > MAX_INSTS) return error.TooComplex;
        for (slice) |inst| {
            try self.insts.append(rebaseInst(inst, 0, new_base));
        }
    }

    fn rebaseInst(inst: Inst, old_base: u32, new_base: u32) Inst {
        return switch (inst) {
            .jmp => |t| .{ .jmp = t - old_base + new_base },
            .split => |s| .{ .split = .{
                .a = s.a - old_base + new_base,
                .b = s.b - old_base + new_base,
            } },
            else => inst,
        };
    }

    fn parseConcat(self: *Compiler) CompileError!void {
        while (self.peek()) |c| {
            if (c == '|' or c == ')') break;
            try self.parseQuantified();
        }
    }

    fn parseQuantified(self: *Compiler) CompileError!void {
        const atom_start = self.insts.items.len;
        try self.parseAtom();
        const atom_end = self.insts.items.len;
        if (atom_end == atom_start) return;

        const c = self.peek() orelse return;
        switch (c) {
            '*', '+', '?' => {
                self.pos += 1;
                var lazy = false;
                if (self.peek() == '?') {
                    self.pos += 1;
                    lazy = true;
                }
                try self.applySimpleQuantifier(atom_start, c, lazy);
            },
            '{' => {
                const saved_pos = self.pos;
                if (self.tryParseBraceQuantifier()) |q| {
                    var lazy = false;
                    if (self.peek() == '?') {
                        self.pos += 1;
                        lazy = true;
                    }
                    try self.applyRangeQuantifier(atom_start, q.min, q.max, lazy);
                } else {
                    // Not a valid {m,n} quantifier; treat '{' as literal next iteration
                    self.pos = saved_pos;
                }
            },
            else => {},
        }
    }

    fn applySimpleQuantifier(self: *Compiler, atom_start: usize, kind: u8, lazy: bool) CompileError!void {
        const atom = try self.extractBranch(atom_start);
        defer self.allocator.free(atom);

        switch (kind) {
            '?' => {
                const split_idx = self.insts.items.len;
                try self.insts.append(.{ .split = .{ .a = 0, .b = 0 } });
                const body_pc: u32 = @intCast(self.insts.items.len);
                try self.appendRelocated(atom, body_pc);
                const after_pc: u32 = @intCast(self.insts.items.len);
                self.insts.items[split_idx] = if (lazy)
                    .{ .split = .{ .a = after_pc, .b = body_pc } }
                else
                    .{ .split = .{ .a = body_pc, .b = after_pc } };
            },
            '*' => {
                const split_idx = self.insts.items.len;
                try self.insts.append(.{ .split = .{ .a = 0, .b = 0 } });
                const body_pc: u32 = @intCast(self.insts.items.len);
                try self.appendRelocated(atom, body_pc);
                try self.insts.append(.{ .jmp = @intCast(split_idx) });
                const after_pc: u32 = @intCast(self.insts.items.len);
                self.insts.items[split_idx] = if (lazy)
                    .{ .split = .{ .a = after_pc, .b = body_pc } }
                else
                    .{ .split = .{ .a = body_pc, .b = after_pc } };
            },
            '+' => {
                const body_pc: u32 = @intCast(self.insts.items.len);
                try self.appendRelocated(atom, body_pc);
                const after_pc: u32 = @intCast(self.insts.items.len + 1);
                try self.insts.append(if (lazy)
                    .{ .split = .{ .a = after_pc, .b = body_pc } }
                else
                    .{ .split = .{ .a = body_pc, .b = after_pc } });
            },
            else => unreachable,
        }
    }

    const BraceQuant = struct { min: usize, max: ?usize };

    fn tryParseBraceQuantifier(self: *Compiler) ?BraceQuant {
        if (self.peek() != '{') return null;
        self.pos += 1;

        const min = self.parseNumber() orelse return null;
        if (min > 64) return null;

        if (self.peek() == '}') {
            self.pos += 1;
            return .{ .min = min, .max = min };
        }
        if (self.peek() != ',') return null;
        self.pos += 1;

        if (self.peek() == '}') {
            self.pos += 1;
            return .{ .min = min, .max = null };
        }
        const max = self.parseNumber() orelse return null;
        if (max < min or max > 64) return null;
        if (self.peek() != '}') return null;
        self.pos += 1;
        return .{ .min = min, .max = max };
    }

    fn parseNumber(self: *Compiler) ?usize {
        var val: usize = 0;
        var count: usize = 0;
        while (self.peek()) |c| {
            if (!std.ascii.isDigit(c)) break;
            val = val * 10 + (c - '0');
            if (val > 256) return null;
            self.pos += 1;
            count += 1;
        }
        if (count == 0) return null;
        return val;
    }

    fn applyRangeQuantifier(self: *Compiler, atom_start: usize, min: usize, max: ?usize, lazy: bool) CompileError!void {
        const atom = try self.extractBranch(atom_start);
        defer self.allocator.free(atom);

        // Emit `min` mandatory copies
        var k: usize = 0;
        while (k < min) : (k += 1) {
            const base: u32 = @intCast(self.insts.items.len);
            try self.appendRelocated(atom, base);
        }

        if (max) |m| {
            // Emit (m - min) optional copies
            var opt: usize = min;
            while (opt < m) : (opt += 1) {
                const split_idx = self.insts.items.len;
                try self.insts.append(.{ .split = .{ .a = 0, .b = 0 } });
                const body_pc: u32 = @intCast(self.insts.items.len);
                try self.appendRelocated(atom, body_pc);
                const after_pc: u32 = @intCast(self.insts.items.len);
                self.insts.items[split_idx] = if (lazy)
                    .{ .split = .{ .a = after_pc, .b = body_pc } }
                else
                    .{ .split = .{ .a = body_pc, .b = after_pc } };
            }
        } else {
            // Unbounded tail: append atom*
            const split_idx = self.insts.items.len;
            try self.insts.append(.{ .split = .{ .a = 0, .b = 0 } });
            const body_pc: u32 = @intCast(self.insts.items.len);
            try self.appendRelocated(atom, body_pc);
            try self.insts.append(.{ .jmp = @intCast(split_idx) });
            const after_pc: u32 = @intCast(self.insts.items.len);
            self.insts.items[split_idx] = if (lazy)
                .{ .split = .{ .a = after_pc, .b = body_pc } }
            else
                .{ .split = .{ .a = body_pc, .b = after_pc } };
        }
    }

    fn parseAtom(self: *Compiler) CompileError!void {
        if (self.insts.items.len >= MAX_INSTS) return error.TooComplex;
        const c = self.peek() orelse return error.UnexpectedEnd;

        switch (c) {
            '(' => {
                self.pos += 1;
                // Optional non-capturing (?:...)
                if (self.pos + 1 < self.pattern.len and self.pattern[self.pos] == '?' and self.pattern[self.pos + 1] == ':') {
                    self.pos += 2;
                }
                try self.parseAlt();
                if (self.peek() != ')') return error.UnmatchedParen;
                self.pos += 1;
            },
            '[' => {
                try self.parseCharClass();
            },
            '.' => {
                self.pos += 1;
                try self.insts.append(.any);
            },
            '^' => {
                self.pos += 1;
                try self.insts.append(.anchor_start);
            },
            '$' => {
                self.pos += 1;
                try self.insts.append(.anchor_end);
            },
            '\\' => {
                self.pos += 1;
                try self.parseEscape();
            },
            '*', '+', '?' => return error.InvalidQuantifier,
            else => {
                self.pos += 1;
                try self.insts.append(.{ .char = c });
            },
        }
    }

    fn addClass(self: *Compiler, cc: CharClass) CompileError!void {
        if (self.classes.items.len >= 65535) return error.TooComplex;
        const id: u16 = @intCast(self.classes.items.len);
        try self.classes.append(cc);
        try self.insts.append(.{ .class = id });
    }

    fn builtinClass(esc: u8) ?CharClass {
        var cc = CharClass{};
        switch (esc) {
            'd' => cc.setRange('0', '9'),
            'D' => {
                cc.setRange('0', '9');
                cc.invert();
            },
            'w' => {
                cc.setRange('a', 'z');
                cc.setRange('A', 'Z');
                cc.setRange('0', '9');
                cc.set('_');
            },
            'W' => {
                cc.setRange('a', 'z');
                cc.setRange('A', 'Z');
                cc.setRange('0', '9');
                cc.set('_');
                cc.invert();
            },
            's' => {
                cc.set(' ');
                cc.set('\t');
                cc.set('\n');
                cc.set('\r');
                cc.set(0x0b);
                cc.set(0x0c);
            },
            'S' => {
                cc.set(' ');
                cc.set('\t');
                cc.set('\n');
                cc.set('\r');
                cc.set(0x0b);
                cc.set(0x0c);
                cc.invert();
            },
            else => return null,
        }
        return cc;
    }

    fn parseEscape(self: *Compiler) CompileError!void {
        const esc = self.peek() orelse return error.UnexpectedEnd;
        self.pos += 1;

        if (builtinClass(esc)) |cc| {
            try self.addClass(cc);
            return;
        }
        switch (esc) {
            'b' => try self.insts.append(.word_boundary),
            'B' => try self.insts.append(.non_word_boundary),
            't' => try self.insts.append(.{ .char = '\t' }),
            'n' => try self.insts.append(.{ .char = '\n' }),
            'r' => try self.insts.append(.{ .char = '\r' }),
            else => try self.insts.append(.{ .char = esc }),
        }
    }

    fn parseCharClass(self: *Compiler) CompileError!void {
        self.pos += 1; // skip '['
        var negated = false;
        if (self.peek() == '^') {
            negated = true;
            self.pos += 1;
        }

        var cc = CharClass{};
        var first = true;
        while (self.peek()) |c| {
            if (c == ']' and !first) {
                self.pos += 1;
                if (self.case_insensitive) cc.addCaseInsensitive();
                if (negated) cc.invert();
                try self.addClass(cc);
                return;
            }
            first = false;

            if (c == '\\') {
                self.pos += 1;
                const esc = self.peek() orelse return error.InvalidClass;
                self.pos += 1;
                if (builtinClass(esc)) |bcc| {
                    cc.merge(bcc);
                    continue;
                }
                const ch: u8 = switch (esc) {
                    't' => '\t',
                    'n' => '\n',
                    'r' => '\r',
                    else => esc,
                };
                cc.set(ch);
            } else {
                self.pos += 1;
                if (self.peek() == '-' and self.pos + 1 < self.pattern.len and self.pattern[self.pos + 1] != ']') {
                    self.pos += 1; // skip '-'
                    const hi = self.peek() orelse return error.InvalidClass;
                    self.pos += 1;
                    if (hi < c) return error.InvalidClass;
                    cc.setRange(c, hi);
                } else {
                    cc.set(c);
                }
            }
        }
        return error.InvalidClass;
    }
};

test "Regex basic, quantifiers, classes, alternation, and anchors" {
    const alloc = std.testing.allocator;

    {
        var re = try Regex.compile(alloc, "fn\\s+([a-zA-Z_][a-zA-Z0-9_]*)\\(", false);
        defer re.deinit();
        const m = (try re.findNext(alloc, "pub fn hello_world(x: i32)", 0)).?;
        try std.testing.expectEqual(@as(usize, 4), m.start);
        try std.testing.expectEqual(@as(usize, 19), m.end);
    }

    {
        var re = try Regex.compile(alloc, "foo|bar", true);
        defer re.deinit();
        var all = try re.findAll(alloc, "FOO baz Bar foo", 100);
        defer all.deinit();
        try std.testing.expectEqual(@as(usize, 3), all.items.len);
        try std.testing.expectEqual(@as(usize, 0), all.items[0].start);
        try std.testing.expectEqual(@as(usize, 8), all.items[1].start);
        try std.testing.expectEqual(@as(usize, 12), all.items[2].start);
    }

    {
        var re = try Regex.compile(alloc, "\\d{2,4}", false);
        defer re.deinit();
        const m = (try re.findNext(alloc, "abc 1 2026 xyz", 0)).?;
        try std.testing.expectEqual(@as(usize, 6), m.start);
        try std.testing.expectEqual(@as(usize, 10), m.end);
    }

    {
        var re = try Regex.compile(alloc, "a+?", false);
        defer re.deinit();
        const m = (try re.findNext(alloc, "aaaa", 0)).?;
        try std.testing.expectEqual(@as(usize, 0), m.start);
        try std.testing.expectEqual(@as(usize, 1), m.end);
    }
}
