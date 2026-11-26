const std = @import("std");

pub const Entry = struct {
    name: []u8,
    path: []u8, // path relative to cwd or root_path suitable for opening
    is_dir: bool,
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
        var exp = Explorer{
            .allocator = allocator,
            .root_path = try allocator.dupe(u8, root_path),
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
        var it = self.expanded.keyIterator();
        while (it.next()) |k| {
            self.allocator.free(k.*);
        }
        self.expanded.deinit();
        self.allocator.free(self.root_path);
    }

    fn clearEntries(self: *Explorer) void {
        for (self.entries.items) |e| {
            self.allocator.free(e.name);
            self.allocator.free(e.path);
        }
        self.entries.clearRetainingCapacity();
    }

    pub fn refresh(self: *Explorer) !void {
        self.clearEntries();
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
                .depth = depth,
                .is_expanded = is_expanded,
            });

            if (is_expanded) {
                try self.scanDir(full_path, depth + 1);
            }
        }
    }

    pub fn moveUp(self: *Explorer) void {
        if (self.selected > 0) self.selected -= 1;
    }

    pub fn moveDown(self: *Explorer) void {
        if (self.selected + 1 < self.entries.items.len) self.selected += 1;
    }

    pub fn ensureVisible(self: *Explorer, view_height: usize) void {
        if (view_height == 0) return;
        if (self.selected < self.scroll) {
            self.scroll = self.selected;
        } else if (self.selected >= self.scroll + view_height) {
            self.scroll = self.selected - view_height + 1;
        }
    }

    /// Toggles directory expansion or returns the file path to open.
    pub fn activateSelected(self: *Explorer) !?[]const u8 {
        if (self.entries.items.len == 0) return null;
        const entry = self.entries.items[self.selected];
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

    pub fn collapseOrParent(self: *Explorer) !void {
        if (self.entries.items.len == 0) return;
        const entry = self.entries.items[self.selected];
        if (entry.is_dir and entry.is_expanded) {
            if (self.expanded.fetchRemove(entry.path)) |kv| {
                self.allocator.free(kv.key);
            }
            try self.refresh();
            return;
        }
        if (entry.depth > 0) {
            var i = self.selected;
            while (i > 0) {
                i -= 1;
                if (self.entries.items[i].depth < entry.depth) {
                    self.selected = i;
                    return;
                }
            }
        }
    }

    pub fn toggleHidden(self: *Explorer) !void {
        self.show_hidden = !self.show_hidden;
        try self.refresh();
    }
};
