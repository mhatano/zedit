const std = @import("std");

pub const Entry = struct {
    name: []u8,
    path: []u8, // path relative to cwd or root_path suitable for opening
    is_dir: bool,
    is_parent: bool = false,
    depth: usize,
    is_expanded: bool,
};

pub const Explorer = struct {
    allocator: std.mem.Allocator,
    root_path: []u8,
    entries: std.ArrayList(Entry),
    expanded: std.StringHashMap(void),
    selected: usize,
    scroll: usize,
    visible: bool,
    focused: bool,
    width: usize,
    show_hidden: bool,

    pub fn init(allocator: std.mem.Allocator, root_path: []const u8) !Explorer {
        const real_root = std.fs.cwd().realpathAlloc(allocator, root_path) catch
            try allocator.dupe(u8, root_path);
        var exp = Explorer{
            .allocator = allocator,
            .root_path = real_root,
            .entries = std.ArrayList(Entry).init(allocator),
            .expanded = std.StringHashMap(void).init(allocator),
            .selected = 0,
            .scroll = 0,
            .visible = true,
            .focused = false,
            .width = 26,
            .show_hidden = false,
        };
        try exp.refresh();
        return exp;
    }

    pub fn deinit(self: *Explorer) void {
        self.clearEntries();
        self.entries.deinit();
        self.clearExpanded();
        self.expanded.deinit();
        self.allocator.free(self.root_path);
    }

    fn clearExpanded(self: *Explorer) void {
        var it = self.expanded.keyIterator();
        while (it.next()) |k| {
            self.allocator.free(k.*);
        }
        self.expanded.clearRetainingCapacity();
    }

    fn clearEntries(self: *Explorer) void {
        for (self.entries.items) |e| {
            self.allocator.free(e.name);
            self.allocator.free(e.path);
        }
        self.entries.clearRetainingCapacity();
    }

    pub fn rootDisplayName(self: *const Explorer) []const u8 {
        const base = std.fs.path.basename(self.root_path);
        if (base.len > 0) return base;
        return self.root_path;
    }

    /// Changes the explorer root directory to `new_dir_path` (resolving relative to current `root_path` or `cwd`).
    pub fn changeRoot(self: *Explorer, new_dir_path: []const u8) !void {
        const candidate = if (std.fs.path.isAbsolute(new_dir_path))
            try self.allocator.dupe(u8, new_dir_path)
        else
            try std.fs.path.join(self.allocator, &.{ self.root_path, new_dir_path });
        defer self.allocator.free(candidate);

        // Verify directory can be opened and resolve canonical path
        const resolved = std.fs.cwd().realpathAlloc(self.allocator, candidate) catch blk: {
            // Also try relative to process cwd directly
            break :blk try std.fs.cwd().realpathAlloc(self.allocator, new_dir_path);
        };
        errdefer self.allocator.free(resolved);

        var dir = try std.fs.cwd().openDir(resolved, .{});
        dir.close();

        self.allocator.free(self.root_path);
        self.root_path = resolved;
        self.clearExpanded();
        self.selected = 0;
        self.scroll = 0;
        try self.refresh();
    }

    /// Navigates up to the parent directory of `root_path`.
    pub fn goParent(self: *Explorer) !bool {
        if (std.fs.path.dirname(self.root_path)) |parent| {
            if (!std.mem.eql(u8, parent, self.root_path)) {
                const parent_copy = try self.allocator.dupe(u8, parent);
                defer self.allocator.free(parent_copy);
                try self.changeRoot(parent_copy);
                return true;
            }
        }
        // Fallback: join ".."
        const up = try std.fs.path.join(self.allocator, &.{ self.root_path, ".." });
        defer self.allocator.free(up);
        const resolved = std.fs.cwd().realpathAlloc(self.allocator, up) catch return false;
        defer self.allocator.free(resolved);
        if (std.mem.eql(u8, resolved, self.root_path)) return false;
        try self.changeRoot(resolved);
        return true;
    }

    /// Changes root directory into the currently selected directory entry (or parent if `..` is selected).
    pub fn enterSelectedDir(self: *Explorer) !bool {
        if (self.entries.items.len == 0) return false;
        const entry = self.entries.items[self.selected];
        if (entry.is_parent) {
            return try self.goParent();
        }
        if (entry.is_dir) {
            const target = try self.allocator.dupe(u8, entry.path);
            defer self.allocator.free(target);
            try self.changeRoot(target);
            return true;
        }
        return false;
    }

    pub fn refresh(self: *Explorer) !void {
        self.clearEntries();
        // Always prepend ".." entry at top so user can navigate to parent directory via mouse or Enter
        try self.entries.append(.{
            .name = try self.allocator.dupe(u8, ".. (parent dir)"),
            .path = try self.allocator.dupe(u8, ".."),
            .is_dir = true,
            .is_parent = true,
            .depth = 0,
            .is_expanded = false,
        });
        try self.scanDir(self.root_path, 0);
        if (self.entries.items.len == 0) {
            self.selected = 0;
            self.scroll = 0;
        } else if (self.selected >= self.entries.items.len) {
            self.selected = self.entries.items.len - 1;
        }
    }

    const RawItem = struct {
        name: []u8,
        is_dir: bool,
    };

    fn itemLessThan(_: void, a: RawItem, b: RawItem) bool {
        if (a.is_dir != b.is_dir) return a.is_dir;
        return std.ascii.lessThanIgnoreCase(a.name, b.name);
    }

    fn shouldSkip(self: *const Explorer, name: []const u8) bool {
        if (self.show_hidden) return false;
        if (name.len > 0 and name[0] == '.') return true;
        if (std.mem.eql(u8, name, "node_modules")) return true;
        if (std.mem.eql(u8, name, "zig-out")) return true;
        if (std.mem.eql(u8, name, "zig-cache")) return true;
        if (std.mem.eql(u8, name, "target")) return true;
        return false;
    }

    fn scanDir(self: *Explorer, dir_path: []const u8, depth: usize) !void {
        if (depth > 16) return;

        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();

        var items = std.ArrayList(RawItem).init(self.allocator);
        defer {
            for (items.items) |it| self.allocator.free(it.name);
            items.deinit();
        }

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            if (self.shouldSkip(entry.name)) continue;
            const is_dir = (entry.kind == .directory);
            try items.append(.{
                .name = try self.allocator.dupe(u8, entry.name),
                .is_dir = is_dir,
            });
        }

        std.mem.sort(RawItem, items.items, {}, itemLessThan);

        for (items.items) |it| {
            const full_path = if (std.mem.eql(u8, dir_path, "."))
                try self.allocator.dupe(u8, it.name)
            else
                try std.fs.path.join(self.allocator, &.{ dir_path, it.name });
            errdefer self.allocator.free(full_path);

            const name_copy = try self.allocator.dupe(u8, it.name);
            errdefer self.allocator.free(name_copy);

            const is_expanded = it.is_dir and self.expanded.contains(full_path);
            try self.entries.append(.{
                .name = name_copy,
                .path = full_path,
                .is_dir = it.is_dir,
                .is_parent = false,
                .depth = depth,
                .is_expanded = is_expanded,
            });

            if (is_expanded) {
                try self.scanDir(full_path, depth + 1);
            }
        }
    }

    pub fn moveUp(self: *Explorer, view_height: usize) void {
        if (self.selected > 0) self.selected -= 1;
        self.ensureVisible(view_height);
    }

    pub fn moveDown(self: *Explorer, view_height: usize) void {
        if (self.selected + 1 < self.entries.items.len) self.selected += 1;
        self.ensureVisible(view_height);
    }

    pub fn pageUp(self: *Explorer, view_height: usize) void {
        const step = @max(view_height, 1);
        self.selected -|= step;
        self.ensureVisible(view_height);
    }

    pub fn pageDown(self: *Explorer, view_height: usize) void {
        if (self.entries.items.len == 0) return;
        const step = @max(view_height, 1);
        self.selected = @min(self.selected + step, self.entries.items.len - 1);
        self.ensureVisible(view_height);
    }

    pub fn moveHome(self: *Explorer, view_height: usize) void {
        self.selected = 0;
        self.ensureVisible(view_height);
    }

    pub fn moveEnd(self: *Explorer, view_height: usize) void {
        if (self.entries.items.len > 0) {
            self.selected = self.entries.items.len - 1;
        }
        self.ensureVisible(view_height);
    }

    pub fn scrollBy(self: *Explorer, delta: isize, view_height: usize) void {
        if (self.entries.items.len == 0 or view_height == 0) {
            self.scroll = 0;
            return;
        }
        const max_scroll = if (self.entries.items.len > view_height)
            self.entries.items.len - view_height
        else
            0;
        if (delta < 0) {
            const sub: usize = @intCast(-delta);
            self.scroll -|= sub;
        } else {
            const add: usize = @intCast(delta);
            self.scroll = @min(self.scroll + add, max_scroll);
        }
    }

    pub fn clampScroll(self: *Explorer, view_height: usize) void {
        if (self.entries.items.len == 0 or view_height == 0) {
            self.scroll = 0;
            return;
        }
        const max_scroll = if (self.entries.items.len > view_height)
            self.entries.items.len - view_height
        else
            0;
        if (self.scroll > max_scroll) {
            self.scroll = max_scroll;
        }
    }

    pub fn ensureVisible(self: *Explorer, view_height: usize) void {
        if (view_height == 0) return;
        if (self.selected < self.scroll) {
            self.scroll = self.selected;
        } else if (self.selected >= self.scroll + view_height) {
            self.scroll = self.selected - view_height + 1;
        }
        self.clampScroll(view_height);
    }

    /// Toggles directory expansion (or navigates to parent if `..` is selected) or returns the file path to open.
    pub fn activateSelected(self: *Explorer) !?[]const u8 {
        if (self.entries.items.len == 0) return null;
        const entry = self.entries.items[self.selected];
        if (entry.is_parent) {
            _ = try self.goParent();
            return null;
        }
        if (entry.is_dir) {
            if (self.expanded.fetchRemove(entry.path)) |kv| {
                self.allocator.free(kv.key);
            } else {
                const key = try self.allocator.dupe(u8, entry.path);
                try self.expanded.put(key, {});
            }
            try self.refresh();
            return null;
        }
        return entry.path;
    }

    pub fn collapseOrParent(self: *Explorer, view_height: usize) !void {
        if (self.entries.items.len == 0) return;
        const entry = self.entries.items[self.selected];
        if (entry.is_parent) {
            _ = try self.goParent();
            return;
        }
        if (entry.is_dir and entry.is_expanded) {
            if (self.expanded.fetchRemove(entry.path)) |kv| {
                self.allocator.free(kv.key);
            }
            try self.refresh();
            self.ensureVisible(view_height);
            return;
        }
        if (entry.depth > 0) {
            var i = self.selected;
            while (i > 0) {
                i -= 1;
                if (!self.entries.items[i].is_parent and self.entries.items[i].depth < entry.depth) {
                    self.selected = i;
                    self.ensureVisible(view_height);
                    return;
                }
            }
        }
    }

    pub fn toggleHidden(self: *Explorer) !void {
        self.show_hidden = !self.show_hidden;
        try self.refresh();
    }

    pub const MIN_WIDTH: usize = 16;

    pub fn setWidth(self: *Explorer, new_w: usize, term_cols: usize) void {
        const max_w = if (term_cols > 24) @min(term_cols - 16, 80) else MIN_WIDTH;
        self.width = std.math.clamp(new_w, MIN_WIDTH, @max(MIN_WIDTH, max_w));
    }

    pub fn resizeBy(self: *Explorer, delta: isize, term_cols: usize) void {
        const cur: isize = @intCast(self.width);
        const target: usize = if (cur + delta < @as(isize, @intCast(MIN_WIDTH)))
            MIN_WIDTH
        else
            @intCast(cur + delta);
        self.setWidth(target, term_cols);
    }
};
