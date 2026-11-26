const std = @import("std");
const Editor = @import("editor.zig").Editor;

pub const VERSION = "0.1.0";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var files = std.ArrayList([]const u8).init(allocator);
    defer files.deinit();

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printHelp();
            return;
        }
        if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            const stdout = std.io.getStdOut().writer();
            try stdout.print("zedit {s}\n", .{VERSION});
            return;
        }
        try files.append(arg);
    }

    var editor = try Editor.init(allocator, files.items);
    defer editor.deinit();

    try editor.run();
}

fn printHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\zedit — Compact, speedy, multi-platform programmer's terminal editor (Zig)
        \\
        \\Usage:
        \\  zedit [files or directory...]
        \\  zedit --help | --version
        \\
        \\Keybindings:
        \\  Ctrl+S            Save file (Save As if untitled)
        \\  Ctrl+O            Open file
        \\  Ctrl+N            New tab / buffer
        \\  Ctrl+W            Close current tab
        \\  Ctrl+Q            Quit (press twice if unsaved changes exist)
        \\  Alt+Left/Right    Switch tabs (or Ctrl+Tab / Alt+1..9)
        \\  Ctrl+B            Toggle file explorer sidebar
        \\  Ctrl+E            Focus / unfocus file explorer sidebar
        \\  Ctrl+F            Incremental search (Alt+R Regex, Alt+C Case, F3/Shift+F3 Next/Prev)
        \\  Ctrl+H            Incremental search & replace (Tab switch, Enter replace, Alt+A all)
        \\  Ctrl+G            Go to line[:col]
        \\  Ctrl+U / F2       Select & lock file encoding (Auto, UTF-8, Shift_JIS, EUC-JP, ISO-2022-JP, UTF-16)
        \\  Ctrl+Z / Ctrl+Y   Undo / Redo (Ctrl+Shift+Z also Redo)
        \\  Ctrl+C / X / V    Copy / Cut / Paste (with OSC 52 clipboard sync)
        \\  Ctrl+A            Select all
        \\  Ctrl+D            Duplicate line or selection
        \\  Ctrl+K            Delete current line
        \\  Shift+Arrows      Extend selection (Ctrl+Left/Right word jump)
        \\  Tab / Shift+Tab   Indent / Unindent (works on multi-line selections)
        \\
    );
}

test {
    _ = @import("encoding.zig");
    _ = @import("buffer.zig");
    _ = @import("regex.zig");
    _ = @import("syntax.zig");
    _ = @import("explorer.zig");
    _ = @import("terminal.zig");
    _ = @import("editor.zig");
}
