const std = @import("std");
const BufferMod = @import("buffer.zig");
const Buffer = BufferMod.TextBuffer;
const Range = BufferMod.Range;
const Syntax = @import("syntax.zig");
const Regex = @import("regex.zig").Regex;
const Match = @import("regex.zig").Match;
const Explorer = @import("explorer.zig").Explorer;
const Term = @import("terminal.zig");

const TAB_WIDTH: usize = 4;

const BracketPair = struct {
    a: usize,
    b: usize,
};

pub const PanelMode = enum {
    none,
    find,
    replace,
    prompt_open,
    prompt_save_as,
    prompt_goto,
};

const TabHit = struct {
    buf_idx: usize,
    x_start: usize,
    x_end: usize,
    close_x: usize,
};

pub const Editor = struct {
    allocator: std.mem.Allocator,
    term: Term.Terminal,
    buffers: std.ArrayList(Buffer),
    active_idx: usize,
    next_untitled_id: usize,
    explorer: Explorer,

    running: bool,
    dirty: bool,
    clear_screen_on_render: bool,
    quit_confirm: bool,
    close_confirm: bool,

    // Clipboard
    clipboard: std.ArrayList(u8),

    // Status message
    status_msg: [256]u8,
    status_msg_len: usize,
    status_is_err: bool,
    status_expire_ms: i64,

    // Bottom panel (Find / Replace / Prompts)
    panel: PanelMode,
    panel_focus_replace: bool,
    find_input: std.ArrayList(u8),
    replace_input: std.ArrayList(u8),
    prompt_input: std.ArrayList(u8),
    search_regex: bool,
    search_case_sensitive: bool,
    search_err: bool,
    matches: std.ArrayList(Match),
    current_match_idx: ?usize,

    // Mouse / layout caches
    tab_hits: std.ArrayList(TabHit),
    last_gutter_w: usize,
    last_editor_x: usize,
    last_editor_rows: usize,
    mouse_dragging: bool,

    // Reusable render buffers (zero heap churn per frame)
    frame_buf: std.ArrayList(u8),
    line_scratch: std.ArrayList(u8),
    token_scratch: std.ArrayList(Syntax.TokenKind),
    state_scratch: std.ArrayList(Syntax.LineState),

    pub fn init(allocator: std.mem.Allocator, initial_files: []const []const u8) !Editor {
        var term = try Term.Terminal.init(allocator);
        errdefer term.deinit();

        var explorer = try Explorer.init(allocator, ".");
        errdefer explorer.deinit();

        var ed = Editor{
            .allocator = allocator,
            .term = term,
            .buffers = std.ArrayList(Buffer).init(allocator),
            .active_idx = 0,
            .next_untitled_id = 1,
            .explorer = explorer,
            .running = true,
            .dirty = true,
            .clear_screen_on_render = true,
            .quit_confirm = false,
            .close_confirm = false,
            .clipboard = std.ArrayList(u8).init(allocator),
            .status_msg = undefined,
            .status_msg_len = 0,
            .status_is_err = false,
            .status_expire_ms = 0,
            .panel = .none,
            .panel_focus_replace = false,
            .find_input = std.ArrayList(u8).init(allocator),
            .replace_input = std.ArrayList(u8).init(allocator),
            .prompt_input = std.ArrayList(u8).init(allocator),
            .search_regex = false,
            .search_case_sensitive = false,
            .search_err = false,
            .matches = std.ArrayList(Match).init(allocator),
            .current_match_idx = null,
            .tab_hits = std.ArrayList(TabHit).init(allocator),
            .last_gutter_w = 5,
            .last_editor_x = 0,
            .last_editor_rows = 20,
            .mouse_dragging = false,
            .frame_buf = std.ArrayList(u8).init(allocator),
            .line_scratch = std.ArrayList(u8).init(allocator),
            .token_scratch = std.ArrayList(Syntax.TokenKind).init(allocator),
            .state_scratch = std.ArrayList(Syntax.LineState).init(allocator),
        };
        errdefer ed.deinit();

        // Hide sidebar automatically if terminal is narrow
        if (ed.term.last_size.cols < 70) {
            ed.explorer.visible = false;
        }

        if (initial_files.len == 0) {
            try ed.newBuffer();
            ed.setStatus("zedit ready — Ctrl+O Open │ Ctrl+F Find │ Ctrl+B Tree │ Ctrl+S Save │ Ctrl+Q Quit", false);
        } else {
            for (initial_files) |arg| {
                // Check if arg is a directory
                if (std.fs.cwd().openDir(arg, .{})) |dir_val| {
                    var d = dir_val;
                    d.close();
                    ed.explorer.deinit();
                    ed.explorer = try Explorer.init(allocator, arg);
                    ed.explorer.visible = true;
                    continue;
                } else |_| {}
                try ed.openFile(arg);
            }
            if (ed.buffers.items.len == 0) {
                try ed.newBuffer();
            }
        }

        return ed;
    }

    pub fn deinit(self: *Editor) void {
        for (self.buffers.items) |*b| b.deinit();
        self.buffers.deinit();
        self.explorer.deinit();
        self.clipboard.deinit();
        self.find_input.deinit();
        self.replace_input.deinit();
        self.prompt_input.deinit();
        self.matches.deinit();
        self.tab_hits.deinit();
        self.frame_buf.deinit();
        self.line_scratch.deinit();
        self.token_scratch.deinit();
        self.state_scratch.deinit();
        self.term.deinit();
    }

    pub fn run(self: *Editor) !void {
        while (self.running) {
            if (self.dirty) {
                try self.render();
                self.dirty = false;
            }

            const ev = try self.term.readEvent(50);
            switch (ev) {
                .none => {
                    if (self.status_msg_len > 0 and self.status_expire_ms > 0 and std.time.milliTimestamp() >= self.status_expire_ms) {
                        self.status_msg_len = 0;
                        self.dirty = true;
                    }
                },
                .resize => {
                    self.clear_screen_on_render = true;
                    self.dirty = true;
                },
                .key => |k| {
                    try self.handleKey(k);
                    self.dirty = true;
                },
                .mouse => |m| {
                    try self.handleMouse(m);
                    self.dirty = true;
                },
                .paste => |text| {
                    try self.handlePaste(text);
                    self.dirty = true;
                },
            }
        }
    }

    fn activeBuf(self: *Editor) *Buffer {
        return &self.buffers.items[self.active_idx];
    }

    fn setStatus(self: *Editor, msg: []const u8, is_err: bool) void {
        const n = @min(msg.len, self.status_msg.len);
        @memcpy(self.status_msg[0..n], msg[0..n]);
        self.status_msg_len = n;
        self.status_is_err = is_err;
        self.status_expire_ms = std.time.milliTimestamp() + 4500;
    }

    fn setStatusFmt(self: *Editor, is_err: bool, comptime fmt: []const u8, args: anytype) void {
        const s = std.fmt.bufPrint(&self.status_msg, fmt, args) catch self.status_msg[0..0];
        self.status_msg_len = s.len;
        self.status_is_err = is_err;
        self.status_expire_ms = std.time.milliTimestamp() + 4500;
    }

    // --- Buffer / Tab Management ---

    fn newBuffer(self: *Editor) !void {
        const b = try Buffer.init(self.allocator, self.next_untitled_id);
        self.next_untitled_id += 1;
        try self.buffers.append(b);
        self.active_idx = self.buffers.items.len - 1;
        self.explorer.focused = false;
        self.invalidateSearch();
    }

    fn openFile(self: *Editor, path: []const u8) !void {
        // Focus existing tab if already open
        for (self.buffers.items, 0..) |*b, idx| {
            if (b.path) |p| {
                if (std.mem.eql(u8, p, path)) {
                    self.active_idx = idx;
                    self.explorer.focused = false;
                    self.setStatusFmt(false, "Switched to {s}", .{b.displayName()});
                    try self.refreshSearchIfActive();
                    return;
                }
            }
        }

        const loaded = Buffer.loadFile(self.allocator, path) catch |err| {
            self.setStatusFmt(true, "Failed to open {s}: {s}", .{ path, @errorName(err) });
            return;
        };

        // Replace an untouched empty untitled buffer if it's the only buffer
        if (self.buffers.items.len == 1 and
            self.buffers.items[0].path == null and
            self.buffers.items[0].len() == 0 and
            !self.buffers.items[0].isModified())
        {
            self.buffers.items[0].deinit();
            self.buffers.items[0] = loaded;
            self.active_idx = 0;
        } else {
            try self.buffers.append(loaded);
            self.active_idx = self.buffers.items.len - 1;
        }
        self.explorer.focused = false;
        self.setStatusFmt(false, "Opened {s} ({d} lines)", .{ self.activeBuf().displayName(), self.activeBuf().lineCount() });
        try self.refreshSearchIfActive();
    }

    fn saveActive(self: *Editor) !void {
        const buf = self.activeBuf();
        if (buf.path == null) {
            self.panel = .prompt_save_as;
            self.prompt_input.clearRetainingCapacity();
            return;
        }
        buf.save() catch |err| {
            self.setStatusFmt(true, "Save failed: {s}", .{@errorName(err)});
            return;
        };
        self.setStatusFmt(false, "Saved {s} ({d} lines)", .{ buf.displayName(), buf.lineCount() });
        self.explorer.refresh() catch {};
    }

    fn closeTab(self: *Editor, idx: usize) !void {
        if (idx >= self.buffers.items.len) return;
        const buf = &self.buffers.items[idx];
        if (buf.isModified() and !self.close_confirm) {
            self.close_confirm = true;
            self.setStatusFmt(true, "'{s}' has unsaved changes! Press Ctrl+W again to close anyway", .{buf.displayName()});
            return;
        }
        self.close_confirm = false;
        var removed = self.buffers.orderedRemove(idx);
        removed.deinit();
        if (self.buffers.items.len == 0) {
            try self.newBuffer();
        } else if (self.active_idx >= self.buffers.items.len) {
            self.active_idx = self.buffers.items.len - 1;
        }
        try self.refreshSearchIfActive();
    }

    fn requestQuit(self: *Editor) void {
        var unsaved: usize = 0;
        for (self.buffers.items) |*b| {
            if (b.isModified()) unsaved += 1;
        }
        if (unsaved > 0 and !self.quit_confirm) {
            self.quit_confirm = true;
            self.setStatusFmt(true, "{d} unsaved buffer(s)! Press Ctrl+Q again to quit without saving", .{unsaved});
            return;
        }
        self.running = false;
    }

    // --- Input Handling ---

    fn handleKey(self: *Editor, k: Term.KeyEvent) !void {
        // Reset double-press confirmations on unrelated keys
        if (!(k.ctrl and k.code == .char and k.code.char == 'q')) self.quit_confirm = false;
        if (!(k.ctrl and k.code == .char and k.code.char == 'w')) self.close_confirm = false;

        // Global shortcuts that work regardless of focus
        if (k.ctrl and !k.alt) {
            switch (k.code) {
                .char => |ch| switch (std.ascii.toLower(@intCast(@min(ch, 127)))) {
                    'q' => {
                        self.requestQuit();
                        return;
                    },
                    's' => {
                        try self.saveActive();
                        return;
                    },
                    'n' => {
                        try self.newBuffer();
                        return;
                    },
                    'w' => {
                        try self.closeTab(self.active_idx);
                        return;
                    },
                    'o' => {
                        self.panel = .prompt_open;
                        self.prompt_input.clearRetainingCapacity();
                        self.explorer.focused = false;
                        return;
                    },
                    'g' => {
                        self.panel = .prompt_goto;
                        self.prompt_input.clearRetainingCapacity();
                        self.explorer.focused = false;
                        return;
                    },
                    'b' => {
                        self.explorer.visible = !self.explorer.visible;
                        if (!self.explorer.visible) self.explorer.focused = false;
                        return;
                    },
                    'e' => {
                        if (!self.explorer.visible) {
                            self.explorer.visible = true;
                            self.explorer.focused = true;
                        } else {
                            self.explorer.focused = !self.explorer.focused;
                        }
                        if (self.explorer.focused) self.panel = .none;
                        return;
                    },
                    'f' => {
                        try self.openFindPanel(false);
                        return;
                    },
                    'h' => {
                        try self.openFindPanel(true);
                        return;
                    },
                    else => {},
                },
                .tab => {
                    if (self.buffers.items.len > 1) {
                        if (k.shift) {
                            self.active_idx = if (self.active_idx == 0) self.buffers.items.len - 1 else self.active_idx - 1;
                        } else {
                            self.active_idx = (self.active_idx + 1) % self.buffers.items.len;
                        }
                        try self.refreshSearchIfActive();
                    }
                    return;
                },
                else => {},
            }
        }

        // Alt shortcuts (tab switching, sidebar scrolling, search toggles)
        if (k.alt and !k.ctrl) {
            const view_h = if (self.last_editor_rows > 1) self.last_editor_rows - 1 else 1;
            switch (k.code) {
                .up => {
                    if (!self.explorer.visible) self.explorer.visible = true;
                    self.explorer.moveUp(view_h);
                    return;
                },
                .down => {
                    if (!self.explorer.visible) self.explorer.visible = true;
                    self.explorer.moveDown(view_h);
                    return;
                },
                .page_up => {
                    if (!self.explorer.visible) self.explorer.visible = true;
                    self.explorer.pageUp(view_h);
                    return;
                },
                .page_down => {
                    if (!self.explorer.visible) self.explorer.visible = true;
                    self.explorer.pageDown(view_h);
                    return;
                },
                .left => {
                    if (self.buffers.items.len > 1) {
                        self.active_idx = if (self.active_idx == 0) self.buffers.items.len - 1 else self.active_idx - 1;
                        try self.refreshSearchIfActive();
                    }
                    return;
                },
                .right => {
                    if (self.buffers.items.len > 1) {
                        self.active_idx = (self.active_idx + 1) % self.buffers.items.len;
                        try self.refreshSearchIfActive();
                    }
                    return;
                },
                .char => |ch| {
                    if (ch >= '1' and ch <= '9') {
                        const target: usize = @intCast(ch - '1');
                        if (target < self.buffers.items.len) {
                            self.active_idx = target;
                            try self.refreshSearchIfActive();
                        }
                        return;
                    }
                },
                else => {},
            }
        }

        // F3 / Shift+F3 search navigation anywhere
        if (k.code == .f3) {
            if (self.matches.items.len > 0) {
                self.jumpMatch(!k.shift);
            }
            return;
        }
        if (k.code == .f1) {
            self.setStatus("Keys: ^S Save │ ^O Open │ ^N New │ ^W Close │ ^F Find │ ^H Replace │ ^B/^E Tree (Alt+↑/↓) │ Alt+←/→ Tabs │ ^Q Quit", false);
            return;
        }

        // Route to active panel, explorer, or editor buffer
        if (self.panel != .none) {
            try self.handlePanelKey(k);
            return;
        }
        if (self.explorer.visible and self.explorer.focused) {
            try self.handleExplorerKey(k);
            return;
        }
        try self.handleEditorKey(k);
    }

    fn handleExplorerKey(self: *Editor, k: Term.KeyEvent) !void {
        const view_h = if (self.last_editor_rows > 1) self.last_editor_rows - 1 else 1;
        switch (k.code) {
            .escape, .tab => self.explorer.focused = false,
            .up => self.explorer.moveUp(view_h),
            .down => self.explorer.moveDown(view_h),
            .page_up => self.explorer.pageUp(view_h),
            .page_down => self.explorer.pageDown(view_h),
            .home => self.explorer.moveHome(view_h),
            .end => self.explorer.moveEnd(view_h),
            .enter, .right => {
                if (try self.explorer.activateSelected()) |file_path| {
                    const duped = try self.allocator.dupe(u8, file_path);
                    defer self.allocator.free(duped);
                    try self.openFile(duped);
                }
                self.explorer.ensureVisible(view_h);
            },
            .left => try self.explorer.collapseOrParent(view_h),
            .char => |ch| {
                if (ch == 'j') {
                    self.explorer.moveDown(view_h);
                } else if (ch == 'k') {
                    self.explorer.moveUp(view_h);
                } else if (ch == 'g') {
                    self.explorer.moveHome(view_h);
                } else if (ch == 'G') {
                    self.explorer.moveEnd(view_h);
                } else if (ch == ' ') {
                    if (try self.explorer.activateSelected()) |file_path| {
                        const duped = try self.allocator.dupe(u8, file_path);
                        defer self.allocator.free(duped);
                        try self.openFile(duped);
                    }
                    self.explorer.ensureVisible(view_h);
                } else if (ch == '.') {
                    try self.explorer.toggleHidden();
                    self.explorer.ensureVisible(view_h);
                    self.setStatus(if (self.explorer.show_hidden) "Explorer: showing hidden files" else "Explorer: hiding dotfiles", false);
                } else if (ch == 'r') {
                    try self.explorer.refresh();
                    self.explorer.ensureVisible(view_h);
                    self.setStatus("Explorer refreshed", false);
                }
            },
            else => {},
        }
    }

    fn handlePanelKey(self: *Editor, k: Term.KeyEvent) !void {
        // Search/replace Alt toggles
        if (k.alt and (self.panel == .find or self.panel == .replace)) {
            if (k.code == .char) {
                const lo = std.ascii.toLower(@intCast(@min(k.code.char, 127)));
                if (lo == 'r') {
                    self.search_regex = !self.search_regex;
                    try self.runSearch(true);
                    return;
                }
                if (lo == 'c') {
                    self.search_case_sensitive = !self.search_case_sensitive;
                    try self.runSearch(true);
                    return;
                }
                if (lo == 'a' and self.panel == .replace) {
                    try self.replaceAll();
                    return;
                }
            }
        }

        if (k.code == .escape) {
            self.panel = .none;
            return;
        }

        switch (self.panel) {
            .find, .replace => {
                if (k.code == .tab and self.panel == .replace) {
                    self.panel_focus_replace = !self.panel_focus_replace;
                    return;
                }
                if (k.code == .up) {
                    self.jumpMatch(false);
                    return;
                }
                if (k.code == .down) {
                    self.jumpMatch(true);
                    return;
                }
                if (k.code == .enter) {
                    if (self.panel == .replace and self.panel_focus_replace) {
                        try self.replaceCurrent();
                    } else {
                        self.jumpMatch(!k.shift);
                    }
                    return;
                }

                const target = if (self.panel == .replace and self.panel_focus_replace) &self.replace_input else &self.find_input;
                const changed = try editLineInput(target, k);
                if (changed and target == &self.find_input) {
                    try self.runSearch(true);
                }
            },
            .prompt_open, .prompt_save_as, .prompt_goto => {
                if (k.code == .enter) {
                    const text = std.mem.trim(u8, self.prompt_input.items, " \t");
                    const mode = self.panel;
                    self.panel = .none;
                    if (text.len == 0) return;
                    const duped = try self.allocator.dupe(u8, text);
                    defer self.allocator.free(duped);

                    switch (mode) {
                        .prompt_open => try self.openFile(duped),
                        .prompt_save_as => {
                            try self.activeBuf().setPath(duped);
                            try self.saveActive();
                        },
                        .prompt_goto => self.gotoLineSpec(duped),
                        else => {},
                    }
                    return;
                }
                _ = try editLineInput(&self.prompt_input, k);
            },
            .none => {},
        }
    }

    fn editLineInput(input: *std.ArrayList(u8), k: Term.KeyEvent) !bool {
        if (k.ctrl) {
            if (k.code == .char and k.code.char == 'u') {
                input.clearRetainingCapacity();
                return true;
            }
            return false;
        }
        switch (k.code) {
            .backspace => {
                if (input.items.len > 0) {
                    var n = input.items.len - 1;
                    while (n > 0 and (input.items[n] & 0xC0) == 0x80) n -= 1;
                    input.shrinkRetainingCapacity(n);
                    return true;
                }
            },
            .char => |cp| {
                if (!k.alt and cp >= 0x20) {
                    var utf8_buf: [4]u8 = undefined;
                    const n = std.unicode.utf8Encode(cp, &utf8_buf) catch return false;
                    try input.appendSlice(utf8_buf[0..n]);
                    return true;
                }
            },
            else => {},
        }
        return false;
    }

    fn handleEditorKey(self: *Editor, k: Term.KeyEvent) !void {
        const buf = self.activeBuf();

        // Ctrl editing commands
        if (k.ctrl and !k.alt) {
            switch (k.code) {
                .char => |ch| switch (std.ascii.toLower(@intCast(@min(ch, 127)))) {
                    'a' => {
                        buf.anchor = 0;
                        buf.cursor = buf.len();
                        buf.preferred_col = null;
                        return;
                    },
                    'z' => {
                        if (k.shift) {
                            if (try buf.redo()) self.setStatus("Redo", false);
                        } else {
                            if (try buf.undo()) self.setStatus("Undo", false);
                        }
                        buf.preferred_col = null;
                        try self.refreshSearchIfActive();
                        return;
                    },
                    'y' => {
                        if (try buf.redo()) self.setStatus("Redo", false);
                        buf.preferred_col = null;
                        try self.refreshSearchIfActive();
                        return;
                    },
                    'c' => {
                        try self.copySelectionOrLine(false);
                        return;
                    },
                    'x' => {
                        try self.copySelectionOrLine(true);
                        try self.refreshSearchIfActive();
                        return;
                    },
                    'v' => {
                        try self.pasteText(self.clipboard.items);
                        try self.refreshSearchIfActive();
                        return;
                    },
                    'd' => {
                        try self.duplicateLineOrSelection();
                        try self.refreshSearchIfActive();
                        return;
                    },
                    'k' => {
                        try self.deleteCurrentLine();
                        try self.refreshSearchIfActive();
                        return;
                    },
                    else => {},
                },
                .left => {
                    self.prepareMove(k.shift);
                    buf.cursor = buf.prevWordOffset(buf.cursor);
                    buf.preferred_col = null;
                    self.ensureCursorVisible();
                    return;
                },
                .right => {
                    self.prepareMove(k.shift);
                    buf.cursor = buf.nextWordOffset(buf.cursor);
                    buf.preferred_col = null;
                    self.ensureCursorVisible();
                    return;
                },
                .home => {
                    self.prepareMove(k.shift);
                    buf.cursor = 0;
                    buf.preferred_col = null;
                    self.ensureCursorVisible();
                    return;
                },
                .end => {
                    self.prepareMove(k.shift);
                    buf.cursor = buf.len();
                    buf.preferred_col = null;
                    self.ensureCursorVisible();
                    return;
                },
                .backspace => {
                    if (try buf.deleteSelection()) {
                        // deleted selection
                    } else {
                        const target = buf.prevWordOffset(buf.cursor);
                        if (target < buf.cursor) {
                            try buf.delete(target, buf.cursor - target);
                        }
                    }
                    buf.preferred_col = null;
                    self.ensureCursorVisible();
                    try self.refreshSearchIfActive();
                    return;
                },
                else => {},
            }
        }

        if (k.alt and k.code == .backspace) {
            const target = buf.prevWordOffset(buf.cursor);
            if (target < buf.cursor) {
                try buf.delete(target, buf.cursor - target);
            }
            buf.preferred_col = null;
            self.ensureCursorVisible();
            try self.refreshSearchIfActive();
            return;
        }

        // Navigation & standard keys
        switch (k.code) {
            .escape => {
                buf.anchor = null;
                self.matches.clearRetainingCapacity();
                self.current_match_idx = null;
            },
            .left => {
                if (!k.shift and buf.selectionRange() != null) {
                    const sel = buf.selectionRange().?;
                    buf.cursor = sel.start;
                    buf.anchor = null;
                } else {
                    self.prepareMove(k.shift);
                    buf.cursor = buf.prevCharOffset(buf.cursor);
                }
                buf.preferred_col = null;
                self.ensureCursorVisible();
            },
            .right => {
                if (!k.shift and buf.selectionRange() != null) {
                    const sel = buf.selectionRange().?;
                    buf.cursor = sel.end;
                    buf.anchor = null;
                } else {
                    self.prepareMove(k.shift);
                    buf.cursor = buf.nextCharOffset(buf.cursor);
                }
                buf.preferred_col = null;
                self.ensureCursorVisible();
            },
            .up => {
                self.prepareMove(k.shift);
                self.moveVertical(-1);
                self.ensureCursorVisible();
            },
            .down => {
                self.prepareMove(k.shift);
                self.moveVertical(1);
                self.ensureCursorVisible();
            },
            .home => {
                self.prepareMove(k.shift);
                const lc = buf.offsetToLineCol(buf.cursor);
                const r = buf.lineRange(lc.line);
                // Smart Home: toggle between first non-whitespace and col 0
                var indent_end = r.start;
                while (indent_end < r.end and (buf.byteAt(indent_end) == ' ' or buf.byteAt(indent_end) == '\t')) {
                    indent_end += 1;
                }
                buf.cursor = if (buf.cursor == indent_end) r.start else indent_end;
                buf.preferred_col = null;
                self.ensureCursorVisible();
            },
            .end => {
                self.prepareMove(k.shift);
                const lc = buf.offsetToLineCol(buf.cursor);
                const r = buf.lineRange(lc.line);
                buf.cursor = r.end;
                buf.preferred_col = null;
                self.ensureCursorVisible();
            },
            .page_up => {
                self.prepareMove(k.shift);
                const step: isize = -@as(isize, @intCast(@max(self.last_editor_rows, 5) - 2));
                self.moveVertical(step);
                self.ensureCursorVisible();
            },
            .page_down => {
                self.prepareMove(k.shift);
                const step: isize = @intCast(@max(self.last_editor_rows, 5) - 2);
                self.moveVertical(step);
                self.ensureCursorVisible();
            },
            .backspace => {
                if (try buf.deleteSelection()) {
                    // done
                } else if (buf.cursor > 0) {
                    const prev = buf.prevCharOffset(buf.cursor);
                    try buf.delete(prev, buf.cursor - prev);
                }
                buf.preferred_col = null;
                self.ensureCursorVisible();
                try self.refreshSearchIfActive();
            },
            .delete => {
                if (try buf.deleteSelection()) {
                    // done
                } else if (buf.cursor < buf.len()) {
                    const next = buf.nextCharOffset(buf.cursor);
                    try buf.delete(buf.cursor, next - buf.cursor);
                }
                buf.preferred_col = null;
                self.ensureCursorVisible();
                try self.refreshSearchIfActive();
            },
            .enter => {
                try self.insertNewlineWithIndent();
                buf.preferred_col = null;
                self.ensureCursorVisible();
                try self.refreshSearchIfActive();
            },
            .tab => {
                try self.handleTab(k.shift);
                buf.preferred_col = null;
                self.ensureCursorVisible();
                try self.refreshSearchIfActive();
            },
            .char => |cp| {
                if (!k.ctrl and !k.alt and cp >= 0x20) {
                    var utf8_buf: [4]u8 = undefined;
                    const n = std.unicode.utf8Encode(cp, &utf8_buf) catch return;
                    if (buf.selectionRange() != null) {
                        buf.beginGroup();
                        defer buf.endGroup();
                        _ = try buf.deleteSelection();
                        try buf.insert(buf.cursor, utf8_buf[0..n]);
                    } else {
                        try buf.insert(buf.cursor, utf8_buf[0..n]);
                    }
                    buf.preferred_col = null;
                    self.ensureCursorVisible();
                    try self.refreshSearchIfActive();
                }
            },
            else => {},
        }
    }

    fn prepareMove(self: *Editor, shift: bool) void {
        const buf = self.activeBuf();
        if (shift) {
            if (buf.anchor == null) buf.anchor = buf.cursor;
        } else {
            buf.anchor = null;
        }
    }

    fn moveVertical(self: *Editor, delta: isize) void {
        const buf = self.activeBuf();
        const lc = buf.offsetToLineCol(buf.cursor);
        const target_vcol = buf.preferred_col orelse self.byteColToVisual(buf, lc.line, lc.col);
        buf.preferred_col = target_vcol;

        const max_line = buf.lineCount() - 1;
        const new_line_i = @as(isize, @intCast(lc.line)) + delta;
        const new_line: usize = if (new_line_i < 0) 0 else @min(@as(usize, @intCast(new_line_i)), max_line);

        const new_col = self.visualToByteCol(buf, new_line, target_vcol);
        buf.cursor = buf.lineColToOffset(new_line, new_col);
    }

    fn insertNewlineWithIndent(self: *Editor) !void {
        const buf = self.activeBuf();
        buf.beginGroup();
        defer buf.endGroup();

        _ = try buf.deleteSelection();
        const lc = buf.offsetToLineCol(buf.cursor);
        const r = buf.lineRange(lc.line);

        // Collect leading whitespace on current line up to cursor
        var indent = std.ArrayList(u8).init(self.allocator);
        defer indent.deinit();
        try indent.append('\n');

        var p = r.start;
        while (p < buf.cursor and p < r.end) : (p += 1) {
            const c = buf.byteAt(p);
            if (c == ' ' or c == '\t') {
                try indent.append(c);
            } else break;
        }

        // Add extra indent level if last non-space char before cursor opens a block
        var check = buf.cursor;
        while (check > r.start and (buf.byteAt(check - 1) == ' ' or buf.byteAt(check - 1) == '\t')) {
            check -= 1;
        }
        if (check > r.start) {
            const last_ch = buf.byteAt(check - 1);
            if (last_ch == '{' or last_ch == '[' or last_ch == '(' or last_ch == ':') {
                try indent.appendSlice("    ");
            }
        }

        try buf.insert(buf.cursor, indent.items);
    }

    fn handleTab(self: *Editor, unindent: bool) !void {
        const buf = self.activeBuf();
        if (buf.selectionRange()) |sel| {
            const start_lc = buf.offsetToLineCol(sel.start);
            var end_lc = buf.offsetToLineCol(sel.end);
            if (end_lc.line > start_lc.line and end_lc.col == 0) {
                end_lc.line -= 1;
            }
            buf.beginGroup();
            defer buf.endGroup();

            var row: usize = end_lc.line + 1;
            while (row > start_lc.line) {
                row -= 1;
                const r = buf.lineRange(row);
                if (!unindent) {
                    try buf.insert(r.start, "    ");
                } else {
                    const rm = countRemovableIndent(buf, r.start, r.end);
                    if (rm > 0) try buf.delete(r.start, rm);
                }
            }
            const new_start = buf.lineRange(start_lc.line).start;
            const new_end = buf.lineRange(end_lc.line).end;
            buf.anchor = new_start;
            buf.cursor = new_end;
            return;
        }

        if (!unindent) {
            try buf.insert(buf.cursor, "    ");
        } else {
            const lc = buf.offsetToLineCol(buf.cursor);
            const r = buf.lineRange(lc.line);
            const rm = countRemovableIndent(buf, r.start, r.end);
            if (rm > 0) {
                const saved_col = if (lc.col >= rm) lc.col - rm else 0;
                try buf.delete(r.start, rm);
                buf.cursor = buf.lineColToOffset(lc.line, saved_col);
            }
        }
    }

    fn countRemovableIndent(buf: *const Buffer, start: usize, end: usize) usize {
        if (start >= end) return 0;
        if (buf.byteAt(start) == '\t') return 1;
        var spaces: usize = 0;
        while (start + spaces < end and spaces < TAB_WIDTH and buf.byteAt(start + spaces) == ' ') {
            spaces += 1;
        }
        return spaces;
    }

    fn copySelectionOrLine(self: *Editor, cut: bool) !void {
        const buf = self.activeBuf();
        self.clipboard.clearRetainingCapacity();

        if (buf.selectionRange()) |sel| {
            const slice = try buf.copyRangeAlloc(self.allocator, sel.start, sel.end - sel.start);
            defer self.allocator.free(slice);
            try self.clipboard.appendSlice(slice);
            self.term.copyOsc52(self.clipboard.items);
            if (cut) {
                _ = try buf.deleteSelection();
                self.setStatusFmt(false, "Cut {d} bytes", .{self.clipboard.items.len});
            } else {
                self.setStatusFmt(false, "Copied {d} bytes", .{self.clipboard.items.len});
            }
        } else {
            // Copy/cut entire current line
            const lc = buf.offsetToLineCol(buf.cursor);
            const r = buf.lineRange(lc.line);
            const slice = try buf.copyRangeAlloc(self.allocator, r.start, r.end_with_nl - r.start);
            defer self.allocator.free(slice);
            try self.clipboard.appendSlice(slice);
            if (self.clipboard.items.len == 0 or self.clipboard.items[self.clipboard.items.len - 1] != '\n') {
                try self.clipboard.append('\n');
            }
            self.term.copyOsc52(self.clipboard.items);
            if (cut) {
                try buf.delete(r.start, r.end_with_nl - r.start);
                self.setStatus("Cut line", false);
            } else {
                self.setStatus("Copied line", false);
            }
        }
    }

    fn handlePaste(self: *Editor, raw: []const u8) !void {
        if (self.panel != .none) {
            // Paste first line into active input field
            const nl = std.mem.indexOfAny(u8, raw, "\r\n") orelse raw.len;
            const target = switch (self.panel) {
                .find => &self.find_input,
                .replace => if (self.panel_focus_replace) &self.replace_input else &self.find_input,
                .prompt_open, .prompt_save_as, .prompt_goto => &self.prompt_input,
                .none => return,
            };
            try target.appendSlice(raw[0..nl]);
            if (target == &self.find_input) try self.runSearch(true);
            return;
        }
        try self.pasteText(raw);
        try self.refreshSearchIfActive();
    }

    fn pasteText(self: *Editor, raw: []const u8) !void {
        if (raw.len == 0) return;
        // Normalize CRLF -> LF
        var norm = std.ArrayList(u8).init(self.allocator);
        defer norm.deinit();
        try norm.ensureTotalCapacity(raw.len);
        var i: usize = 0;
        while (i < raw.len) : (i += 1) {
            if (raw[i] == '\r') {
                if (i + 1 < raw.len and raw[i + 1] == '\n') continue;
                try norm.append('\n');
            } else {
                try norm.append(raw[i]);
            }
        }

        const buf = self.activeBuf();
        buf.beginGroup();
        defer buf.endGroup();
        _ = try buf.deleteSelection();
        try buf.insert(buf.cursor, norm.items);
        buf.preferred_col = null;
        self.ensureCursorVisible();
    }

    fn duplicateLineOrSelection(self: *Editor) !void {
        const buf = self.activeBuf();
        if (buf.selectionRange()) |sel| {
            const slice = try buf.copyRangeAlloc(self.allocator, sel.start, sel.end - sel.start);
            defer self.allocator.free(slice);
            buf.anchor = null;
            try buf.insert(sel.end, slice);
        } else {
            const lc = buf.offsetToLineCol(buf.cursor);
            const r = buf.lineRange(lc.line);
            const line_bytes = try buf.copyRangeAlloc(self.allocator, r.start, r.end - r.start);
            defer self.allocator.free(line_bytes);
            var dup = std.ArrayList(u8).init(self.allocator);
            defer dup.deinit();
            try dup.append('\n');
            try dup.appendSlice(line_bytes);
            try buf.insert(r.end, dup.items);
        }
        self.ensureCursorVisible();
    }

    fn deleteCurrentLine(self: *Editor) !void {
        const buf = self.activeBuf();
        const lc = buf.offsetToLineCol(buf.cursor);
        const r = buf.lineRange(lc.line);
        buf.anchor = null;
        if (r.end_with_nl > r.start) {
            try buf.delete(r.start, r.end_with_nl - r.start);
        } else if (r.start > 0) {
            // Last empty line: remove preceding newline
            try buf.delete(r.start - 1, 1);
        }
        self.ensureCursorVisible();
    }

    fn gotoLineSpec(self: *Editor, spec: []const u8) void {
        const buf = self.activeBuf();
        var it = std.mem.splitScalar(u8, spec, ':');
        const line_str = it.next() orelse return;
        const col_str = it.next();

        const line_num = std.fmt.parseInt(usize, line_str, 10) catch {
            self.setStatus("Invalid line number", true);
            return;
        };
        const target_line = if (line_num > 0) @min(line_num - 1, buf.lineCount() - 1) else 0;
        const target_col: usize = if (col_str) |cs| blk: {
            const c = std.fmt.parseInt(usize, cs, 10) catch 1;
            break :blk if (c > 0) c - 1 else 0;
        } else 0;

        buf.anchor = null;
        buf.cursor = buf.lineColToOffset(target_line, target_col);
        buf.preferred_col = null;
        self.ensureCursorVisible();
        self.setStatusFmt(false, "Line {d}", .{target_line + 1});
    }

    // --- Incremental Search & Replace ---

    fn openFindPanel(self: *Editor, with_replace: bool) !void {
        self.explorer.focused = false;
        self.panel = if (with_replace) .replace else .find;
        self.panel_focus_replace = false;

        // Pre-fill from single-line selection if active
        const buf = self.activeBuf();
        if (buf.selectionRange()) |sel| {
            if (sel.end - sel.start <= 128) {
                const slice = try buf.copyRangeAlloc(self.allocator, sel.start, sel.end - sel.start);
                defer self.allocator.free(slice);
                if (std.mem.indexOfScalar(u8, slice, '\n') == null) {
                    self.find_input.clearRetainingCapacity();
                    try self.find_input.appendSlice(slice);
                }
            }
        }
        try self.runSearch(true);
    }

    fn invalidateSearch(self: *Editor) void {
        self.matches.clearRetainingCapacity();
        self.current_match_idx = null;
        self.search_err = false;
    }

    fn refreshSearchIfActive(self: *Editor) !void {
        if (self.panel == .find or self.panel == .replace or self.matches.items.len > 0) {
            try self.runSearch(false);
        }
    }

    fn runSearch(self: *Editor, jump_to_nearest: bool) !void {
        self.matches.clearRetainingCapacity();
        self.current_match_idx = null;
        self.search_err = false;

        const query = self.find_input.items;
        if (query.len == 0) return;

        const buf = self.activeBuf();
        const text = try buf.toOwnedSlice(self.allocator);
        defer self.allocator.free(text);

        if (self.search_regex) {
            var re = Regex.compile(self.allocator, query, !self.search_case_sensitive) catch {
                self.search_err = true;
                return;
            };
            defer re.deinit();
            var found = try re.findAll(self.allocator, text, 10_000);
            defer found.deinit();
            try self.matches.appendSlice(found.items);
        } else {
            var pos: usize = 0;
            while (pos + query.len <= text.len and self.matches.items.len < 10_000) {
                const found_idx = if (self.search_case_sensitive)
                    std.mem.indexOfPos(u8, text, pos, query)
                else
                    indexOfIgnoreCase(text, pos, query);
                const idx = found_idx orelse break;
                try self.matches.append(.{ .start = idx, .end = idx + query.len });
                pos = idx + @max(query.len, 1);
            }
        }

        if (self.matches.items.len == 0) return;

        // Pick match at or after cursor
        var pick: usize = 0;
        for (self.matches.items, 0..) |m, idx| {
            if (m.start >= buf.cursor) {
                pick = idx;
                break;
            }
        }
        self.current_match_idx = pick;
        if (jump_to_nearest) {
            const m = self.matches.items[pick];
            buf.anchor = null;
            buf.cursor = m.start;
            self.ensureCursorVisible();
        }
    }

    fn indexOfIgnoreCase(haystack: []const u8, start: usize, needle: []const u8) ?usize {
        if (needle.len == 0) return start;
        if (start + needle.len > haystack.len) return null;
        const first_lo = std.ascii.toLower(needle[0]);
        var i = start;
        const limit = haystack.len - needle.len;
        while (i <= limit) : (i += 1) {
            if (std.ascii.toLower(haystack[i]) == first_lo) {
                if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) {
                    return i;
                }
            }
        }
        return null;
    }

    fn jumpMatch(self: *Editor, forward: bool) void {
        if (self.matches.items.len == 0) return;
        const cur = self.current_match_idx orelse 0;
        const next = if (forward)
            (cur + 1) % self.matches.items.len
        else if (cur == 0)
            self.matches.items.len - 1
        else
            cur - 1;
        self.current_match_idx = next;
        const m = self.matches.items[next];
        const buf = self.activeBuf();
        buf.anchor = null;
        buf.cursor = m.start;
        self.ensureCursorVisible();
    }

    fn replaceCurrent(self: *Editor) !void {
        if (self.matches.items.len == 0) return;
        const idx = self.current_match_idx orelse 0;
        const m = self.matches.items[idx];
        const buf = self.activeBuf();

        buf.beginGroup();
        try buf.delete(m.start, m.end - m.start);
        try buf.insert(m.start, self.replace_input.items);
        buf.endGroup();

        buf.cursor = m.start + self.replace_input.items.len;
        try self.runSearch(true);
        self.setStatus("Replaced 1 occurrence", false);
    }

    fn replaceAll(self: *Editor) !void {
        if (self.matches.items.len == 0) {
            self.setStatus("No matches to replace", false);
            return;
        }
        const buf = self.activeBuf();
        const count = self.matches.items.len;

        buf.beginGroup();
        defer buf.endGroup();

        var i = count;
        while (i > 0) {
            i -= 1;
            const m = self.matches.items[i];
            try buf.delete(m.start, m.end - m.start);
            try buf.insert(m.start, self.replace_input.items);
        }

        try self.runSearch(false);
        self.setStatusFmt(false, "Replaced {d} occurrence(s)", .{count});
    }

    // --- Mouse Handling ---

    fn handleMouse(self: *Editor, m: Term.MouseEvent) !void {
        const size = self.term.getSize();
        const buf = self.activeBuf();

        const view_h = if (self.last_editor_rows > 1) self.last_editor_rows - 1 else 1;

        if (m.kind == .scroll_up) {
            if (self.explorer.visible and m.x < self.explorer.width) {
                self.explorer.scrollBy(-3, view_h);
            } else {
                buf.scroll_row -|= 3;
            }
            return;
        }
        if (m.kind == .scroll_down) {
            if (self.explorer.visible and m.x < self.explorer.width) {
                self.explorer.scrollBy(3, view_h);
            } else {
                const max_scroll = if (buf.lineCount() > 1) buf.lineCount() - 1 else 0;
                buf.scroll_row = @min(buf.scroll_row + 3, max_scroll);
            }
            return;
        }

        if (m.kind == .release) {
            self.mouse_dragging = false;
            return;
        }

        // Click on top tab bar (y == 0)
        if (m.kind == .press and m.y == 0) {
            if (m.x < 4) {
                self.explorer.visible = !self.explorer.visible;
                return;
            }
            for (self.tab_hits.items) |hit| {
                if (m.x >= hit.x_start and m.x < hit.x_end) {
                    if (m.x == hit.close_x) {
                        try self.closeTab(hit.buf_idx);
                    } else {
                        self.active_idx = hit.buf_idx;
                        self.explorer.focused = false;
                        try self.refreshSearchIfActive();
                    }
                    return;
                }
            }
            return;
        }

        // Click in sidebar
        if (m.kind == .press and self.explorer.visible and size.cols >= 50 and m.x < self.explorer.width) {
            self.explorer.focused = true;
            self.panel = .none;
            if (m.y == 1) {
                // Click on EXPLORER header: focus sidebar and scroll buttons if clicked near right edge
                if (m.x + 4 >= self.explorer.width) {
                    self.explorer.pageDown(view_h);
                } else if (m.x + 8 >= self.explorer.width) {
                    self.explorer.pageUp(view_h);
                }
                return;
            }
            if (m.y >= 2 and m.y < 1 + self.last_editor_rows) {
                const idx = self.explorer.scroll + (m.y - 2);
                if (idx < self.explorer.entries.items.len) {
                    self.explorer.selected = idx;
                    if (try self.explorer.activateSelected()) |path| {
                        const duped = try self.allocator.dupe(u8, path);
                        defer self.allocator.free(duped);
                        try self.openFile(duped);
                    }
                    self.explorer.ensureVisible(view_h);
                }
            }
            return;
        }

        // Click / drag inside editor viewport
        if (m.y >= 1 and m.y < 1 + self.last_editor_rows and m.x >= self.last_editor_x + self.last_gutter_w) {
            self.explorer.focused = false;
            const row = buf.scroll_row + (m.y - 1);
            const clamped_row = @min(row, buf.lineCount() - 1);
            const vcol = buf.scroll_col + (m.x - (self.last_editor_x + self.last_gutter_w));
            const byte_col = self.visualToByteCol(buf, clamped_row, vcol);
            const new_offset = buf.lineColToOffset(clamped_row, byte_col);

            if (m.kind == .press) {
                buf.anchor = new_offset;
                buf.cursor = new_offset;
                self.mouse_dragging = true;
            } else if (m.kind == .drag and self.mouse_dragging) {
                buf.cursor = new_offset;
            }
            buf.preferred_col = null;
        }
    }

    // --- Visual Column & Scrolling Helpers ---

    fn byteColToVisual(self: *Editor, buf: *Buffer, line: usize, byte_col: usize) usize {
        const text = buf.readLine(line, &self.line_scratch) catch return byte_col;
        const limit = @min(byte_col, text.len);
        var vcol: usize = 0;
        var i: usize = 0;
        while (i < limit) {
            if (text[i] == '\t') {
                vcol += TAB_WIDTH - (vcol % TAB_WIDTH);
                i += 1;
            } else {
                const dec = decodeCharWidth(text[i..limit]);
                vcol += dec.width;
                i += dec.byte_len;
            }
        }
        return vcol;
    }

    fn visualToByteCol(self: *Editor, buf: *Buffer, line: usize, target_vcol: usize) usize {
        const text = buf.readLine(line, &self.line_scratch) catch return 0;
        var vcol: usize = 0;
        var i: usize = 0;
        while (i < text.len) {
            if (vcol >= target_vcol) break;
            if (text[i] == '\t') {
                const next_v = vcol + TAB_WIDTH - (vcol % TAB_WIDTH);
                if (next_v > target_vcol) break;
                vcol = next_v;
                i += 1;
            } else {
                const dec = decodeCharWidth(text[i..]);
                if (vcol + dec.width > target_vcol) break;
                vcol += dec.width;
                i += dec.byte_len;
            }
        }
        return i;
    }

    fn ensureCursorVisible(self: *Editor) void {
        const size = self.term.getSize();
        const panel_rows = self.panelRows();
        const ed_rows = if (size.rows > 2 + panel_rows) size.rows - 2 - panel_rows else 1;
        const sidebar_w: usize = if (self.explorer.visible and size.cols >= 50) self.explorer.width + 1 else 0;
        const ed_cols = if (size.cols > sidebar_w + self.last_gutter_w) size.cols - sidebar_w - self.last_gutter_w else 1;

        const buf = self.activeBuf();
        const lc = buf.offsetToLineCol(buf.cursor);
        const vcol = self.byteColToVisual(buf, lc.line, lc.col);

        if (lc.line < buf.scroll_row) {
            buf.scroll_row = lc.line;
        } else if (lc.line >= buf.scroll_row + ed_rows) {
            buf.scroll_row = lc.line - ed_rows + 1;
        }

        if (vcol < buf.scroll_col) {
            buf.scroll_col = vcol;
        } else if (vcol + 2 > buf.scroll_col + ed_cols) {
            buf.scroll_col = (vcol + 2) - ed_cols;
        }
    }

    fn panelRows(self: *const Editor) usize {
        return switch (self.panel) {
            .none => 0,
            .find, .prompt_open, .prompt_save_as, .prompt_goto => 1,
            .replace => 2,
        };
    }

    // --- Matching Bracket Finder ---

    fn findMatchingBracket(buf: *const Buffer, cursor: usize) ?BracketPair {
        const total = buf.len();
        if (total == 0) return null;

        var pos: ?usize = null;
        if (cursor < total and isBracket(buf.byteAt(cursor))) {
            pos = cursor;
        } else if (cursor > 0 and isBracket(buf.byteAt(cursor - 1))) {
            pos = cursor - 1;
        }
        const start = pos orelse return null;
        const ch = buf.byteAt(start);

        const pair: struct { target: u8, dir: i2 } = switch (ch) {
            '(' => .{ .target = ')', .dir = 1 },
            '[' => .{ .target = ']', .dir = 1 },
            '{' => .{ .target = '}', .dir = 1 },
            ')' => .{ .target = '(', .dir = -1 },
            ']' => .{ .target = '[', .dir = -1 },
            '}' => .{ .target = '{', .dir = -1 },
            else => return null,
        };

        var depth: usize = 1;
        var steps: usize = 0;
        const MAX_SCAN: usize = 16384;
        var cur = start;

        while (steps < MAX_SCAN) : (steps += 1) {
            if (pair.dir > 0) {
                if (cur + 1 >= total) return null;
                cur += 1;
            } else {
                if (cur == 0) return null;
                cur -= 1;
            }
            const c = buf.byteAt(cur);
            if (c == ch) {
                depth += 1;
            } else if (c == pair.target) {
                depth -= 1;
                if (depth == 0) return .{ .a = start, .b = cur };
            }
        }
        return null;
    }

    fn isBracket(c: u8) bool {
        return c == '(' or c == ')' or c == '[' or c == ']' or c == '{' or c == '}';
    }

    // --- Single-Flush Double-Buffered ANSI Renderer ---

    fn render(self: *Editor) !void {
        const size = self.term.getSize();
        if (size.cols < 10 or size.rows < 4) return;

        self.frame_buf.clearRetainingCapacity();
        const w = self.frame_buf.writer();

        // Synchronized update start + hide cursor + home
        if (self.clear_screen_on_render) {
            try w.writeAll("\x1b[?2026h\x1b[?25l\x1b[0m\x1b[2J\x1b[H");
            self.clear_screen_on_render = false;
        } else {
            try w.writeAll("\x1b[?2026h\x1b[?25l\x1b[H");
        }

        const panel_rows = self.panelRows();
        const ed_rows = if (size.rows > 2 + panel_rows) size.rows - 2 - panel_rows else 1;
        const show_sidebar = self.explorer.visible and size.cols >= 50;
        const sidebar_w: usize = if (show_sidebar) self.explorer.width else 0;
        const ed_x: usize = if (show_sidebar) sidebar_w + 1 else 0;
        const ed_total_w = size.cols - ed_x;

        const buf = self.activeBuf();
        const line_count = buf.lineCount();
        const digits = countDigits(line_count);
        const gutter_w = @max(digits, 3) + 2; // " 123 "
        const code_w = if (ed_total_w > gutter_w) ed_total_w - gutter_w else 1;

        self.last_gutter_w = gutter_w;
        self.last_editor_x = ed_x;
        self.last_editor_rows = ed_rows;

        // Keep cursor in view
        const cursor_lc = buf.offsetToLineCol(buf.cursor);
        const cursor_vcol = self.byteColToVisual(buf, cursor_lc.line, cursor_lc.col);
        if (cursor_lc.line < buf.scroll_row) buf.scroll_row = cursor_lc.line;
        if (cursor_lc.line >= buf.scroll_row + ed_rows) buf.scroll_row = cursor_lc.line - ed_rows + 1;
        if (cursor_vcol < buf.scroll_col) buf.scroll_col = cursor_vcol;
        if (cursor_vcol + 2 > buf.scroll_col + code_w and code_w >= 2) {
            buf.scroll_col = (cursor_vcol + 2) - code_w;
        }

        // 1. Render Top Tab Bar (row 0)
        try self.renderTabBar(w, size.cols);

        // 2. Compute syntax line states up to end of visible window
        const lang = Syntax.Language.detect(buf.path);
        const end_vis_line = @min(buf.scroll_row + ed_rows, line_count);
        try self.computeLineStates(buf, lang, end_vis_line);

        // Precompute bracket match & selection
        const sel = buf.selectionRange();
        const bracket_match = findMatchingBracket(buf, buf.cursor);

        if (show_sidebar) {
            self.explorer.clampScroll(if (ed_rows > 1) ed_rows - 1 else 1);
        }

        // 3. Render Workspace Rows (Sidebar + Code Area)
        var screen_row: usize = 0;
        while (screen_row < ed_rows) : (screen_row += 1) {
            try w.print("\x1b[{d};1H", .{screen_row + 2});

            if (show_sidebar) {
                try self.renderSidebarRow(w, screen_row, sidebar_w, if (ed_rows > 1) ed_rows - 1 else 1);
                // Explicitly position vertical separator at sidebar_w + 1 so wide characters never shift the border
                try w.print("\x1b[{d};{d}H\x1b[48;2;24;24;37m\x1b[38;2;69;71;90m│", .{ screen_row + 2, sidebar_w + 1 });
            }

            const doc_line = buf.scroll_row + screen_row;
            if (doc_line < line_count) {
                try self.renderCodeRow(w, buf, doc_line, cursor_lc.line, lang, gutter_w, code_w, sel, bracket_match);
            } else {
                // Empty tilde row beyond EOF
                try w.writeAll("\x1b[48;2;30;30;46m\x1b[38;2;69;71;90m");
                var gx: usize = 0;
                while (gx + 2 < gutter_w) : (gx += 1) try w.writeByte(' ');
                try w.writeAll("~ ");
                try writeSpaces(w, code_w);
            }
        }

        // 4. Render Bottom Panel (Find / Replace / Prompt)
        if (panel_rows > 0) {
            try self.renderPanel(w, size.rows - panel_rows, size.cols);
        }

        // 5. Render Status Bar (last row)
        try self.renderStatusBar(w, size.rows, size.cols, buf, cursor_lc, lang, sel);

        // 6. Position Hardware Cursor
        try self.positionCursor(w, size, ed_x, gutter_w, ed_rows, cursor_lc, cursor_vcol, buf, panel_rows);

        // Synchronized update end
        try w.writeAll("\x1b[?2026l");

        try self.term.writeAll(self.frame_buf.items);
    }

    fn renderTabBar(self: *Editor, w: anytype, cols: usize) !void {
        self.tab_hits.clearRetainingCapacity();
        try w.writeAll("\x1b[1;1H\x1b[48;2;17;17;27m\x1b[38;2;166;173;200m");

        // Explorer toggle badge
        if (self.explorer.visible) {
            try w.writeAll("\x1b[38;2;137;180;250m ≡ \x1b[38;2;69;71;90m│");
        } else {
            try w.writeAll("\x1b[38;2;108;112;134m ≡ \x1b[38;2;69;71;90m│");
        }
        var col: usize = 4;

        for (self.buffers.items, 0..) |*b, idx| {
            const is_active = (idx == self.active_idx);
            const name = b.displayName();
            const mod = b.isModified();
            const name_w = strDisplayWidth(name);

            // Format: " name ● × " or " name × "
            const tab_len = 1 + name_w + (if (mod) @as(usize, 2) else 0) + 3;
            if (col + tab_len > cols) break;

            const x_start = col;
            if (is_active) {
                try w.writeAll("\x1b[48;2;30;30;46m\x1b[1m\x1b[38;2;205;214;244m ");
            } else {
                try w.writeAll("\x1b[48;2;24;24;37m\x1b[0m\x1b[48;2;24;24;37m\x1b[38;2;147;153;178m ");
            }
            try w.writeAll(name);
            if (mod) {
                try w.writeAll(" \x1b[38;2;249;226;175m●");
            }
            const close_x = x_start + tab_len - 2;
            try w.writeAll(" \x1b[38;2;108;112;134m× \x1b[0m\x1b[48;2;17;17;27m");

            try self.tab_hits.append(.{
                .buf_idx = idx,
                .x_start = x_start,
                .x_end = x_start + tab_len,
                .close_x = close_x,
            });
            col += tab_len;

            if (col < cols) {
                try w.writeAll("\x1b[38;2;49;50;68m│");
                col += 1;
            }
        }

        try w.writeAll("\x1b[0m\x1b[48;2;17;17;27m");
        if (col < cols) try writeSpaces(w, cols - col);
    }

    fn renderSidebarRow(self: *Editor, w: anytype, row: usize, width: usize, view_h: usize) !void {
        if (row == 0) {
            // Explorer header with scroll indicator
            if (self.explorer.focused) {
                try w.writeAll("\x1b[48;2;49;50;68m\x1b[1m\x1b[38;2;137;180;250m");
            } else {
                try w.writeAll("\x1b[48;2;24;24;37m\x1b[1m\x1b[38;2;147;153;178m");
            }
            var hdr_buf: [64]u8 = undefined;
            const total = self.explorer.entries.items.len;
            const title = if (total > view_h)
                std.fmt.bufPrint(&hdr_buf, " EXPLORER ({d}/{d}) ▲▼", .{ self.explorer.selected + 1, total }) catch " EXPLORER"
            else if (self.explorer.show_hidden)
                " EXPLORER [all]"
            else
                " EXPLORER";
            const fit = sliceFittingColumns(title, width);
            try w.writeAll(title[0..fit.bytes]);
            try writeSpaces(w, width - fit.cols);
            try w.writeAll("\x1b[0m");
            return;
        }

        const idx = self.explorer.scroll + (row - 1);
        if (idx >= self.explorer.entries.items.len) {
            try w.writeAll("\x1b[48;2;24;24;37m");
            try writeSpaces(w, width);
            return;
        }

        const entry = self.explorer.entries.items[idx];
        const is_sel = (idx == self.explorer.selected);
        if (is_sel and self.explorer.focused) {
            try w.writeAll("\x1b[48;2;69;71;90m\x1b[38;2;205;214;244m");
        } else if (is_sel) {
            try w.writeAll("\x1b[48;2;40;42;58m\x1b[38;2;205;214;244m");
        } else {
            try w.writeAll("\x1b[48;2;24;24;37m");
        }

        var used: usize = 0;
        const indent = @min(entry.depth * 2 + 1, if (width > 4) width - 4 else 0);
        try writeSpaces(w, indent);
        used += indent;

        if (entry.is_dir) {
            try w.writeAll("\x1b[38;2;137;180;250m");
            if (used + 2 <= width) {
                try w.writeAll(if (entry.is_expanded) "▾ " else "▸ ");
                used += 2;
            }
        } else {
            try w.writeAll("\x1b[38;2;186;194;222m");
            if (used + 2 <= width) {
                try w.writeAll("  ");
                used += 2;
            }
        }

        const avail = if (entry.is_dir and width > used + 1) width - used - 1 else width - used;
        const fit = sliceFittingColumns(entry.name, avail);
        try w.writeAll(entry.name[0..fit.bytes]);
        used += fit.cols;
        if (entry.is_dir and used < width) {
            try w.writeByte('/');
            used += 1;
        }
        if (used < width) try writeSpaces(w, width - used);
        try w.writeAll("\x1b[0m");
    }

    fn computeLineStates(self: *Editor, buf: *Buffer, lang: Syntax.Language, up_to_line: usize) !void {
        self.state_scratch.clearRetainingCapacity();
        if (lang == .plain) {
            try self.state_scratch.appendNTimes(.normal, up_to_line + 1);
            return;
        }
        var state: Syntax.LineState = .normal;
        var row: usize = 0;
        while (row < up_to_line) : (row += 1) {
            try self.state_scratch.append(state);
            const line = try buf.readLine(row, &self.line_scratch);
            try self.token_scratch.resize(line.len);
            state = Syntax.highlightLine(lang, line, state, self.token_scratch.items);
        }
        try self.state_scratch.append(state);
    }

    fn renderCodeRow(
        self: *Editor,
        w: anytype,
        buf: *Buffer,
        doc_line: usize,
        cursor_line: usize,
        lang: Syntax.Language,
        gutter_w: usize,
        code_w: usize,
        sel: ?Range,
        bracket_match: ?BracketPair,
    ) !void {
        const is_cur_line = (doc_line == cursor_line);
        const r = buf.lineRange(doc_line);
        const line = try buf.readLine(doc_line, &self.line_scratch);

        // Gutter (line number)
        if (is_cur_line) {
            try w.writeAll("\x1b[48;2;36;39;58m\x1b[38;2;205;214;244m");
        } else {
            try w.writeAll("\x1b[48;2;30;30;46m\x1b[38;2;88;91;112m");
        }
        var num_buf: [24]u8 = undefined;
        const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{doc_line + 1}) catch "";
        const pad_left = if (gutter_w > num_str.len + 1) gutter_w - num_str.len - 1 else 0;
        try writeSpaces(w, pad_left);
        try w.writeAll(num_str);
        try w.writeByte(' ');

        // Syntax tokenize this line
        const in_state = if (doc_line < self.state_scratch.items.len) self.state_scratch.items[doc_line] else Syntax.LineState.normal;
        try self.token_scratch.resize(line.len);
        _ = Syntax.highlightLine(lang, line, in_state, self.token_scratch.items);

        // Base background for this row
        const base_bg: Syntax.Rgb = if (is_cur_line) .{ .r = 36, .g = 39, .b = 58 } else .{ .r = 30, .g = 30, .b = 46 };
        const sel_bg: Syntax.Rgb = .{ .r = 69, .g = 71, .b = 115 };
        const match_bg: Syntax.Rgb = .{ .r = 98, .g = 86, .b = 44 };
        const active_match_bg: Syntax.Rgb = .{ .r = 180, .g = 120, .b = 40 };
        const bracket_bg: Syntax.Rgb = .{ .r = 88, .g = 91, .b = 112 };

        var last_fg: ?Syntax.Rgb = null;
        var last_bg: ?Syntax.Rgb = null;

        var vcol: usize = 0;
        var drawn: usize = 0;
        var i: usize = 0;

        while (i < line.len and drawn < code_w) {
            const abs_off = r.start + i;
            const tok = self.token_scratch.items[i];
            var fg = Syntax.tokenColor(tok);
            var bg = base_bg;

            // Check search match highlight
            if (self.matchAtOffset(abs_off)) |is_active| {
                bg = if (is_active) active_match_bg else match_bg;
                if (is_active) fg = .{ .r = 17, .g = 17, .b = 27 };
            }
            // Check matching bracket highlight
            if (bracket_match) |bm| {
                if (abs_off == bm.a or abs_off == bm.b) {
                    bg = bracket_bg;
                }
            }
            // Check selection highlight (takes precedence)
            if (sel) |s| {
                if (abs_off >= s.start and abs_off < s.end) {
                    bg = sel_bg;
                }
            }

            if (line[i] == '\t') {
                const spaces = TAB_WIDTH - (vcol % TAB_WIDTH);
                var s_idx: usize = 0;
                while (s_idx < spaces and drawn < code_w) : (s_idx += 1) {
                    if (vcol >= buf.scroll_col) {
                        try emitColors(w, fg, bg, &last_fg, &last_bg);
                        try w.writeByte(' ');
                        drawn += 1;
                    }
                    vcol += 1;
                }
                i += 1;
            } else {
                const dec = decodeCharWidth(line[i..]);
                const cw = dec.width;
                const safe_len = dec.byte_len;

                if (vcol + cw <= buf.scroll_col) {
                    // Character is completely to the left of horizontal scroll offset
                    vcol += cw;
                    i += safe_len;
                    continue;
                }

                if (vcol < buf.scroll_col) {
                    // Wide character straddles the left scroll boundary: emit a space for its right half
                    try emitColors(w, fg, bg, &last_fg, &last_bg);
                    try w.writeByte(' ');
                    drawn += 1;
                    vcol += cw;
                    i += safe_len;
                    continue;
                }

                if (drawn + cw > code_w) {
                    // Wide character does not fit in the remaining 1 column at the right edge
                    try emitColors(w, fg, bg, &last_fg, &last_bg);
                    try writeSpaces(w, code_w - drawn);
                    drawn = code_w;
                    break;
                }

                try emitColors(w, fg, bg, &last_fg, &last_bg);
                if (safe_len == 1 and line[i] < 0x20) {
                    try w.writeByte('?');
                } else {
                    try w.writeAll(line[i .. i + safe_len]);
                }
                drawn += cw;
                vcol += cw;
                i += safe_len;
            }
        }

        // Fill remaining columns to end of row
        if (drawn < code_w) {
            const fill_bg = if (sel != null and r.end >= sel.?.start and r.end < sel.?.end) sel_bg else base_bg;
            try emitColors(w, .{ .r = 205, .g = 214, .b = 244 }, fill_bg, &last_fg, &last_bg);
            try writeSpaces(w, code_w - drawn);
        }
        try w.writeAll("\x1b[0m");
    }

    fn matchAtOffset(self: *const Editor, offset: usize) ?bool {
        if (self.matches.items.len == 0) return null;
        // Binary search for match containing offset
        var lo: usize = 0;
        var hi: usize = self.matches.items.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const m = self.matches.items[mid];
            if (offset < m.start) {
                hi = mid;
            } else if (offset >= m.end) {
                lo = mid + 1;
            } else {
                const is_cur = (self.current_match_idx != null and self.current_match_idx.? == mid);
                return is_cur;
            }
        }
        return null;
    }

    fn emitColors(w: anytype, fg: Syntax.Rgb, bg: Syntax.Rgb, last_fg: *?Syntax.Rgb, last_bg: *?Syntax.Rgb) !void {
        if (last_fg.* == null or last_fg.*.?.r != fg.r or last_fg.*.?.g != fg.g or last_fg.*.?.b != fg.b) {
            try w.print("\x1b[38;2;{d};{d};{d}m", .{ fg.r, fg.g, fg.b });
            last_fg.* = fg;
        }
        if (last_bg.* == null or last_bg.*.?.r != bg.r or last_bg.*.?.g != bg.g or last_bg.*.?.b != bg.b) {
            try w.print("\x1b[48;2;{d};{d};{d}m", .{ bg.r, bg.g, bg.b });
            last_bg.* = bg;
        }
    }

    fn renderPanel(self: *Editor, w: anytype, start_row: usize, cols: usize) !void {
        try w.print("\x1b[{d};1H\x1b[48;2;24;24;37m\x1b[38;2;205;214;244m", .{start_row});

        switch (self.panel) {
            .find, .replace => {
                var line_buf: [512]u8 = undefined;
                const re_flag = if (self.search_regex) "ON" else "off";
                const cs_flag = if (self.search_case_sensitive) "ON" else "off";

                var count_buf: [32]u8 = undefined;
                const count_str = if (self.search_err)
                    "invalid regex"
                else if (self.find_input.items.len == 0)
                    ""
                else if (self.matches.items.len == 0)
                    "no matches"
                else
                    std.fmt.bufPrint(&count_buf, "{d}/{d}", .{ (self.current_match_idx orelse 0) + 1, self.matches.items.len }) catch "";

                const label = if (self.panel == .replace) " Find:    " else " Find: ";
                const right = std.fmt.bufPrint(&line_buf, "  [{s}]  Alt+R:Regex({s})  Alt+C:Case({s})  Esc:Close", .{
                    count_str, re_flag, cs_flag,
                }) catch "";

                try w.writeAll("\x1b[38;2;137;180;250m");
                try w.writeAll(label);
                try w.writeAll("\x1b[38;2;205;214;244m");
                const q_fit = sliceFittingColumns(self.find_input.items, if (cols > label.len + 10) cols - label.len - 10 else 0);
                try w.writeAll(self.find_input.items[0..q_fit.bytes]);
                var used = label.len + q_fit.cols;

                if (self.search_err) {
                    try w.writeAll("\x1b[38;2;243;139;168m");
                } else {
                    try w.writeAll("\x1b[38;2;147;153;178m");
                }
                const r_show = @min(right.len, if (cols > used) cols - used else 0);
                try w.writeAll(right[0..r_show]);
                used += r_show;
                if (used < cols) try writeSpaces(w, cols - used);

                if (self.panel == .replace) {
                    try w.print("\x1b[{d};1H\x1b[48;2;24;24;37m", .{start_row + 1});
                    const rlabel = " Replace: ";
                    const hint = "  Tab:Switch  Enter:Replace  Alt+A:All";
                    try w.writeAll("\x1b[38;2;166;227;161m");
                    try w.writeAll(rlabel);
                    try w.writeAll("\x1b[38;2;205;214;244m");
                    const rep_fit = sliceFittingColumns(self.replace_input.items, if (cols > rlabel.len + 10) cols - rlabel.len - 10 else 0);
                    try w.writeAll(self.replace_input.items[0..rep_fit.bytes]);
                    var rused = rlabel.len + rep_fit.cols;
                    try w.writeAll("\x1b[38;2;147;153;178m");
                    const h_show = @min(hint.len, if (cols > rused) cols - rused else 0);
                    try w.writeAll(hint[0..h_show]);
                    rused += h_show;
                    if (rused < cols) try writeSpaces(w, cols - rused);
                }
            },
            .prompt_open, .prompt_save_as, .prompt_goto => {
                const label = switch (self.panel) {
                    .prompt_open => " Open file: ",
                    .prompt_save_as => " Save as: ",
                    .prompt_goto => " Go to line[:col]: ",
                    else => "",
                };
                try w.writeAll("\x1b[38;2;249;226;175m");
                try w.writeAll(label);
                try w.writeAll("\x1b[38;2;205;214;244m");
                const p_fit = sliceFittingColumns(self.prompt_input.items, if (cols > label.len + 2) cols - label.len - 2 else 0);
                try w.writeAll(self.prompt_input.items[0..p_fit.bytes]);
                const used = label.len + p_fit.cols;
                if (used < cols) try writeSpaces(w, cols - used);
            },
            .none => {},
        }
        try w.writeAll("\x1b[0m");
    }

    fn renderStatusBar(
        self: *Editor,
        w: anytype,
        row: usize,
        cols: usize,
        buf: *const Buffer,
        lc: BufferMod.LineCol,
        lang: Syntax.Language,
        sel: ?Range,
    ) !void {
        try w.print("\x1b[{d};1H\x1b[48;2;17;17;27m", .{row});

        const mode_badge = if (self.panel == .find or self.panel == .replace)
            " FIND "
        else if (self.panel != .none)
            " PROMPT "
        else if (self.explorer.focused)
            " TREE "
        else
            " EDIT ";

        const badge_bg = if (self.explorer.focused)
            "\x1b[48;2;166;227;161m\x1b[38;2;17;17;27m\x1b[1m"
        else if (self.panel != .none)
            "\x1b[48;2;249;226;175m\x1b[38;2;17;17;27m\x1b[1m"
        else
            "\x1b[48;2;137;180;250m\x1b[38;2;17;17;27m\x1b[1m";

        try w.writeAll(badge_bg);
        try w.writeAll(mode_badge);
        try w.writeAll("\x1b[0m\x1b[48;2;17;17;27m ");

        var right_buf: [128]u8 = undefined;
        const eol = if (buf.crlf) "CRLF" else "LF";
        const right_str = if (sel) |s|
            std.fmt.bufPrint(&right_buf, "Sel {d} │ Ln {d}, Col {d} │ {s} │ {s} ", .{
                s.end - s.start, lc.line + 1, lc.col + 1, eol, lang.name(),
            }) catch ""
        else
            std.fmt.bufPrint(&right_buf, "Ln {d}, Col {d} │ {s} │ {s} ", .{
                lc.line + 1, lc.col + 1, eol, lang.name(),
            }) catch "";

        const right_cols = strDisplayWidth(right_str);
        const used_left_prefix = mode_badge.len + 1;
        const max_mid = if (cols > used_left_prefix + right_cols + 1) cols - used_left_prefix - right_cols - 1 else 0;

        var mid_cols: usize = 0;
        if (self.status_msg_len > 0) {
            if (self.status_is_err) {
                try w.writeAll("\x1b[38;2;243;139;168m");
            } else {
                try w.writeAll("\x1b[38;2;166;227;161m");
            }
            const fit = sliceFittingColumns(self.status_msg[0..self.status_msg_len], max_mid);
            try w.writeAll(self.status_msg[0..fit.bytes]);
            mid_cols = fit.cols;
        } else {
            try w.writeAll("\x1b[38;2;166;173;200m");
            const path_str = buf.path orelse buf.displayName();
            const fit = sliceFittingColumns(path_str, max_mid);
            try w.writeAll(path_str[0..fit.bytes]);
            mid_cols = fit.cols;
        }

        const total_left = used_left_prefix + mid_cols;
        if (cols > total_left + right_cols) {
            try writeSpaces(w, cols - total_left - right_cols);
        }
        if (cols >= total_left + right_cols) {
            try w.writeAll("\x1b[38;2;147;153;178m");
            try w.writeAll(right_str);
        }
        try w.writeAll("\x1b[0m");
    }

    fn positionCursor(
        self: *Editor,
        w: anytype,
        size: Term.Size,
        ed_x: usize,
        gutter_w: usize,
        ed_rows: usize,
        lc: @import("buffer.zig").LineCol,
        vcol: usize,
        buf: *const Buffer,
        panel_rows: usize,
    ) !void {
        if (self.panel != .none) {
            const start_row = size.rows - panel_rows;
            switch (self.panel) {
                .find => {
                    const cx = @min(8 + strDisplayWidth(self.find_input.items), size.cols);
                    try w.print("\x1b[{d};{d}H\x1b[?25h", .{ start_row, cx });
                },
                .replace => {
                    if (self.panel_focus_replace) {
                        const cx = @min(11 + strDisplayWidth(self.replace_input.items), size.cols);
                        try w.print("\x1b[{d};{d}H\x1b[?25h", .{ start_row + 1, cx });
                    } else {
                        const cx = @min(11 + strDisplayWidth(self.find_input.items), size.cols);
                        try w.print("\x1b[{d};{d}H\x1b[?25h", .{ start_row, cx });
                    }
                },
                .prompt_open => {
                    const cx = @min(13 + strDisplayWidth(self.prompt_input.items), size.cols);
                    try w.print("\x1b[{d};{d}H\x1b[?25h", .{ start_row, cx });
                },
                .prompt_save_as => {
                    const cx = @min(11 + strDisplayWidth(self.prompt_input.items), size.cols);
                    try w.print("\x1b[{d};{d}H\x1b[?25h", .{ start_row, cx });
                },
                .prompt_goto => {
                    const cx = @min(20 + strDisplayWidth(self.prompt_input.items), size.cols);
                    try w.print("\x1b[{d};{d}H\x1b[?25h", .{ start_row, cx });
                },
                .none => {},
            }
            return;
        }

        if (self.explorer.visible and self.explorer.focused) {
            // Keep cursor hidden in tree mode (row highlight shows selection)
            return;
        }

        if (lc.line >= buf.scroll_row and lc.line < buf.scroll_row + ed_rows and vcol >= buf.scroll_col) {
            const cy = 2 + (lc.line - buf.scroll_row);
            const cx = 1 + ed_x + gutter_w + (vcol - buf.scroll_col);
            if (cx <= size.cols) {
                try w.print("\x1b[{d};{d}H\x1b[?25h", .{ cy, cx });
            }
        }
    }
};

// --- Unicode Display Width (East Asian Width / wcwidth) ---

pub const DecodedChar = struct {
    byte_len: usize,
    width: usize,
};

pub fn decodeCharWidth(bytes: []const u8) DecodedChar {
    if (bytes.len == 0) return .{ .byte_len = 0, .width = 0 };
    const b0 = bytes[0];
    if (b0 < 0x80) {
        return .{ .byte_len = 1, .width = 1 };
    }
    const seq_len = std.unicode.utf8ByteSequenceLength(b0) catch {
        return .{ .byte_len = 1, .width = 1 };
    };
    if (bytes.len < seq_len) {
        return .{ .byte_len = 1, .width = 1 };
    }
    const cp = std.unicode.utf8Decode(bytes[0..seq_len]) catch {
        return .{ .byte_len = 1, .width = 1 };
    };
    return .{ .byte_len = seq_len, .width = codepointWidth(cp) };
}

pub fn codepointWidth(cp: u21) usize {
    if (cp == 0) return 0;
    if (cp < 0x20 or (cp >= 0x7f and cp < 0xa0)) return 1; // rendered as '?'
    // Zero-width combining marks, variation selectors, ZWJ/ZWNJ
    if ((cp >= 0x0300 and cp <= 0x036F) or
        (cp >= 0x1AB0 and cp <= 0x1AFF) or
        (cp >= 0x1DC0 and cp <= 0x1DFF) or
        (cp >= 0x200B and cp <= 0x200F) or
        (cp >= 0x20D0 and cp <= 0x20FF) or
        (cp >= 0xFE00 and cp <= 0xFE0F) or
        (cp >= 0xFE20 and cp <= 0xFE2F) or
        (cp >= 0xE0100 and cp <= 0xE01EF))
    {
        return 0;
    }
    // East Asian Wide (W) and Fullwidth (F) ranges + Emoji
    if (cp >= 0x1100 and
        ((cp <= 0x115F) or // Hangul Jamo
        (cp == 0x2329 or cp == 0x232A) or
        (cp >= 0x231A and cp <= 0x231B) or
        (cp >= 0x23E9 and cp <= 0x23F3) or
        (cp >= 0x25FD and cp <= 0x25FE) or
        (cp >= 0x2614 and cp <= 0x2615) or
        (cp >= 0x2648 and cp <= 0x2653) or
        (cp == 0x267F or cp == 0x2693 or cp == 0x26A1) or
        (cp >= 0x26AA and cp <= 0x26AB) or
        (cp >= 0x26BD and cp <= 0x26BE) or
        (cp >= 0x26C4 and cp <= 0x26C5) or
        (cp == 0x26CE or cp == 0x26D4 or cp == 0x26EA) or
        (cp >= 0x26F2 and cp <= 0x26F5) or
        (cp == 0x26FA or cp == 0x26FD or cp == 0x2705) or
        (cp >= 0x270A and cp <= 0x270B) or
        (cp == 0x2728 or cp == 0x274C or cp == 0x274E) or
        (cp >= 0x2753 and cp <= 0x2755) or
        (cp == 0x2757) or
        (cp >= 0x2795 and cp <= 0x2797) or
        (cp == 0x27B0 or cp == 0x27BF) or
        (cp >= 0x2B1B and cp <= 0x2B1C) or
        (cp == 0x2B50 or cp == 0x2B55) or
        (cp >= 0x2E80 and cp <= 0x303E) or // CJK Radicals, Kangxi, CJK Symbols & Punctuation (、。「」【】)
        (cp >= 0x3040 and cp <= 0x33FF) or // Hiragana, Katakana, Bopomofo, Hangul Compat, Kanbun, CJK Squared
        (cp >= 0x3400 and cp <= 0x4DBF) or // CJK Unified Ideographs Extension A
        (cp >= 0x4E00 and cp <= 0xA4CF) or // CJK Unified Ideographs, Yi
        (cp >= 0xA960 and cp <= 0xA97F) or // Hangul Jamo Extended-A
        (cp >= 0xAC00 and cp <= 0xD7A3) or // Hangul Syllables
        (cp >= 0xF900 and cp <= 0xFAFF) or // CJK Compatibility Ideographs
        (cp >= 0xFE10 and cp <= 0xFE19) or // Vertical forms
        (cp >= 0xFE30 and cp <= 0xFE6F) or // CJK Compatibility Forms
        (cp >= 0xFF01 and cp <= 0xFF60) or // Fullwidth ASCII variants (！～)
        (cp >= 0xFFE0 and cp <= 0xFFE6) or // Fullwidth symbols (￥ etc.)
        (cp >= 0x1F1E6 and cp <= 0x1F1FF) or
        (cp >= 0x1F300 and cp <= 0x1F64F) or // Misc Symbols, Pictographs, Emoticons
        (cp >= 0x1F680 and cp <= 0x1F6FF) or // Transport & Map Symbols
        (cp >= 0x1F900 and cp <= 0x1F9FF) or // Supplemental Symbols and Pictographs
        (cp >= 0x1FA70 and cp <= 0x1FAFF) or
        (cp >= 0x20000 and cp <= 0x3FFFD))) // CJK Unified Ideographs Extensions B..I
    {
        return 2;
    }
    return 1;
}

pub fn strDisplayWidth(s: []const u8) usize {
    var cols: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        const dec = decodeCharWidth(s[i..]);
        cols += dec.width;
        i += dec.byte_len;
    }
    return cols;
}

pub fn sliceFittingColumns(s: []const u8, max_cols: usize) struct { bytes: usize, cols: usize } {
    var cols: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        const dec = decodeCharWidth(s[i..]);
        if (cols + dec.width > max_cols) break;
        cols += dec.width;
        i += dec.byte_len;
    }
    return .{ .bytes = i, .cols = cols };
}

fn writeSpaces(w: anytype, n: usize) !void {
    const spaces = "                                                                ";
    var rem = n;
    while (rem > 0) {
        const chunk = @min(rem, spaces.len);
        try w.writeAll(spaces[0..chunk]);
        rem -= chunk;
    }
}

fn countDigits(n: usize) usize {
    var v = n;
    var d: usize = 1;
    while (v >= 10) : (v /= 10) d += 1;
    return d;
}

test "Unicode display width and UTF-8 column truncation for Japanese CJK text" {
    // Each Japanese character (Hiragana, Katakana, Kanji) occupies 2 terminal columns (3 UTF-8 bytes)
    try std.testing.expectEqual(@as(usize, 12), strDisplayWidth("日本語テスト"));
    try std.testing.expectEqual(@as(usize, 9), strDisplayWidth("あaいbうc"));
    // Half-width katakana (FF61..FF9F) is 1 column
    try std.testing.expectEqual(@as(usize, 3), strDisplayWidth("ｱｲｳ"));

    // Truncating "日本語.zig" (10 cols) to 5 columns should fit "日本" (4 cols, 6 bytes) without splitting a codepoint
    const fit1 = sliceFittingColumns("日本語.zig", 5);
    try std.testing.expectEqual(@as(usize, 6), fit1.bytes);
    try std.testing.expectEqual(@as(usize, 4), fit1.cols);
    try std.testing.expectEqualStrings("日本", "日本語.zig"[0..fit1.bytes]);

    // Truncating to 6 columns should fit "日本語" (6 cols, 9 bytes)
    const fit2 = sliceFittingColumns("日本語.zig", 6);
    try std.testing.expectEqual(@as(usize, 9), fit2.bytes);
    try std.testing.expectEqual(@as(usize, 6), fit2.cols);
}

