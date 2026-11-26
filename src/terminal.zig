const std = @import("std");
const builtin = @import("builtin");

pub const Size = struct {
    cols: usize,
    rows: usize,
};

pub const KeyCode = union(enum) {
    char: u21,
    enter,
    tab,
    backspace,
    delete,
    escape,
    up,
    down,
    left,
    right,
    home,
    end,
    page_up,
    page_down,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
};

pub const KeyEvent = struct {
    code: KeyCode,
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
};

pub const MouseKind = enum {
    press,
    release,
    drag,
    scroll_up,
    scroll_down,
};

pub const MouseEvent = struct {
    kind: MouseKind,
    button: u8,
    x: usize, // 0-indexed column
    y: usize, // 0-indexed row
};

pub const Event = union(enum) {
    none,
    resize,
    key: KeyEvent,
    mouse: MouseEvent,
    paste: []const u8,
};

var g_resized = std.atomic.Value(bool).init(false);

fn handleSigwinch(_: c_int) callconv(.C) void {
    g_resized.store(true, .release);
}

const is_windows = builtin.os.tag == .windows;

const win32 = if (is_windows) struct {
    const w = std.os.windows;
    const HANDLE = w.HANDLE;
    const DWORD = w.DWORD;
    const BOOL = w.BOOL;
    const WORD = w.WORD;
    const SHORT = i16;

    const COORD = extern struct { X: SHORT, Y: SHORT };
    const SMALL_RECT = extern struct { Left: SHORT, Top: SHORT, Right: SHORT, Bottom: SHORT };
    const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
        dwSize: COORD,
        dwCursorPosition: COORD,
        wAttributes: WORD,
        srWindow: SMALL_RECT,
        dwMaximumWindowSize: COORD,
    };

    const ENABLE_PROCESSED_INPUT: DWORD = 0x0001;
    const ENABLE_LINE_INPUT: DWORD = 0x0002;
    const ENABLE_ECHO_INPUT: DWORD = 0x0004;
    const ENABLE_WINDOW_INPUT: DWORD = 0x0008;
    const ENABLE_VIRTUAL_TERMINAL_INPUT: DWORD = 0x0200;

    const ENABLE_PROCESSED_OUTPUT: DWORD = 0x0001;
    const ENABLE_VIRTUAL_TERMINAL_PROCESSING: DWORD = 0x0004;
    const DISABLE_NEWLINE_AUTO_RETURN: DWORD = 0x0008;

    extern "kernel32" fn GetConsoleMode(hConsoleHandle: HANDLE, lpMode: *DWORD) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn SetConsoleMode(hConsoleHandle: HANDLE, dwMode: DWORD) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn GetConsoleScreenBufferInfo(hConsoleOutput: HANDLE, lpConsoleScreenBufferInfo: *CONSOLE_SCREEN_BUFFER_INFO) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn GetNumberOfConsoleInputEvents(hConsoleInput: HANDLE, lpcNumberOfEvents: *DWORD) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD) callconv(w.WINAPI) DWORD;
    extern "kernel32" fn SetConsoleOutputCP(wCodePageID: w.UINT) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn SetConsoleCP(wCodePageID: w.UINT) callconv(w.WINAPI) BOOL;
} else struct {};

pub const Terminal = struct {
    allocator: std.mem.Allocator,
    stdin_file: std.fs.File,
    stdout_file: std.fs.File,
    raw_enabled: bool,

    orig_termios: if (!is_windows) std.posix.termios else void,
    orig_in_mode: if (is_windows) std.os.windows.DWORD else void,
    orig_out_mode: if (is_windows) std.os.windows.DWORD else void,

    last_size: Size,
    in_buf: std.ArrayList(u8),
    paste_buf: std.ArrayList(u8),
    in_paste: bool,

    pub fn init(allocator: std.mem.Allocator) !Terminal {
        var term = Terminal{
            .allocator = allocator,
            .stdin_file = std.io.getStdIn(),
            .stdout_file = std.io.getStdOut(),
            .raw_enabled = false,
            .orig_termios = if (!is_windows) undefined else {},
            .orig_in_mode = if (is_windows) 0 else {},
            .orig_out_mode = if (is_windows) 0 else {},
            .last_size = .{ .cols = 80, .rows = 24 },
            .in_buf = std.ArrayList(u8).init(allocator),
            .paste_buf = std.ArrayList(u8).init(allocator),
            .in_paste = false,
        };
        try term.enableRawMode();
        term.last_size = term.getSize();
        return term;
    }

    pub fn deinit(self: *Terminal) void {
        self.disableRawMode();
        self.in_buf.deinit();
        self.paste_buf.deinit();
    }

    fn enableRawMode(self: *Terminal) !void {
        if (is_windows) {
            const in_h = self.stdin_file.handle;
            const out_h = self.stdout_file.handle;
            _ = win32.SetConsoleOutputCP(65001);
            _ = win32.SetConsoleCP(65001);
            _ = win32.GetConsoleMode(in_h, &self.orig_in_mode);
            _ = win32.GetConsoleMode(out_h, &self.orig_out_mode);

            const new_in = (self.orig_in_mode & ~(win32.ENABLE_ECHO_INPUT | win32.ENABLE_LINE_INPUT | win32.ENABLE_PROCESSED_INPUT)) |
                win32.ENABLE_VIRTUAL_TERMINAL_INPUT | win32.ENABLE_WINDOW_INPUT;
            const new_out = self.orig_out_mode | win32.ENABLE_PROCESSED_OUTPUT |
                win32.ENABLE_VIRTUAL_TERMINAL_PROCESSING | win32.DISABLE_NEWLINE_AUTO_RETURN;
            _ = win32.SetConsoleMode(in_h, new_in);
            _ = win32.SetConsoleMode(out_h, new_out);
        } else {
            const fd = self.stdin_file.handle;
            self.orig_termios = try std.posix.tcgetattr(fd);
            var raw = self.orig_termios;
            raw.iflag.BRKINT = false;
            raw.iflag.ICRNL = false;
            raw.iflag.INPCK = false;
            raw.iflag.ISTRIP = false;
            raw.iflag.IXON = false;
            raw.oflag.OPOST = false;
            raw.cflag.CSIZE = .CS8;
            raw.lflag.ECHO = false;
            raw.lflag.ICANON = false;
            raw.lflag.IEXTEN = false;
            raw.lflag.ISIG = false;
            raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
            raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
            try std.posix.tcsetattr(fd, .FLUSH, raw);

            var sa = std.posix.Sigaction{
                .handler = .{ .handler = handleSigwinch },
                .mask = std.posix.empty_sigset,
                .flags = 0,
            };
            std.posix.sigaction(std.posix.SIG.WINCH, &sa, null);
        }

        self.raw_enabled = true;
        // Enter alternate screen, enable SGR mouse tracking, bracketed paste
        try self.writeAll("\x1b[?1049h\x1b[?1000h\x1b[?1002h\x1b[?1006h\x1b[?2004h\x1b[2J\x1b[H");
    }

    fn disableRawMode(self: *Terminal) void {
        if (!self.raw_enabled) return;
        self.raw_enabled = false;
        // Restore normal screen, show cursor, disable mouse & bracketed paste
        self.writeAll("\x1b[?2004l\x1b[?1006l\x1b[?1002l\x1b[?1000l\x1b[?25h\x1b[0m\x1b[?1049l") catch {};

        if (is_windows) {
            _ = win32.SetConsoleMode(self.stdin_file.handle, self.orig_in_mode);
            _ = win32.SetConsoleMode(self.stdout_file.handle, self.orig_out_mode);
        } else {
            std.posix.tcsetattr(self.stdin_file.handle, .FLUSH, self.orig_termios) catch {};
        }
    }

    pub fn writeAll(self: *Terminal, bytes: []const u8) !void {
        try self.stdout_file.writeAll(bytes);
    }

    pub fn copyOsc52(self: *Terminal, text: []const u8) void {
        if (text.len == 0 or text.len > 65536) return;
        const enc_len = std.base64.standard.Encoder.calcSize(text.len);
        const buf = self.allocator.alloc(u8, enc_len + 16) catch return;
        defer self.allocator.free(buf);
        const prefix = "\x1b]52;c;";
        @memcpy(buf[0..prefix.len], prefix);
        _ = std.base64.standard.Encoder.encode(buf[prefix.len .. prefix.len + enc_len], text);
        buf[prefix.len + enc_len] = 0x07;
        self.writeAll(buf[0 .. prefix.len + enc_len + 1]) catch {};
    }

    pub fn getSize(self: *const Terminal) Size {
        if (is_windows) {
            var info: win32.CONSOLE_SCREEN_BUFFER_INFO = undefined;
            if (win32.GetConsoleScreenBufferInfo(self.stdout_file.handle, &info) != 0) {
                const cols = info.srWindow.Right - info.srWindow.Left + 1;
                const rows = info.srWindow.Bottom - info.srWindow.Top + 1;
                if (cols > 0 and rows > 0) {
                    return .{ .cols = @intCast(cols), .rows = @intCast(rows) };
                }
            }
            return .{ .cols = 80, .rows = 24 };
        } else {
            var ws: std.posix.winsize = undefined;
            const rc = std.posix.system.ioctl(self.stdout_file.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
            if (rc == 0 and ws.col > 0 and ws.row > 0) {
                return .{ .cols = ws.col, .rows = ws.row };
            }
            return .{ .cols = 80, .rows = 24 };
        }
    }

    fn pollInput(self: *Terminal, timeout_ms: i32) bool {
        if (is_windows) {
            const res = win32.WaitForSingleObject(self.stdin_file.handle, @intCast(timeout_ms));
            if (res == 0) {
                var count: std.os.windows.DWORD = 0;
                if (win32.GetNumberOfConsoleInputEvents(self.stdin_file.handle, &count) != 0 and count > 0) {
                    return true;
                }
            }
            return false;
        } else {
            var fds = [_]std.posix.pollfd{.{
                .fd = self.stdin_file.handle,
                .events = std.posix.POLL.IN,
                .revents = 0,
            }};
            const n = std.posix.poll(&fds, timeout_ms) catch return false;
            return n > 0 and (fds[0].revents & std.posix.POLL.IN) != 0;
        }
    }

    fn readMoreBytes(self: *Terminal, timeout_ms: i32) !usize {
        if (!self.pollInput(timeout_ms)) return 0;
        var tmp: [512]u8 = undefined;
        const n = self.stdin_file.read(&tmp) catch |err| {
            if (err == error.WouldBlock) return 0;
            return err;
        };
        if (n > 0) {
            try self.in_buf.appendSlice(tmp[0..n]);
        }
        return n;
    }

    pub fn readEvent(self: *Terminal, timeout_ms: i32) !Event {
        // Check resize
        if (!is_windows and g_resized.swap(false, .acquire)) {
            self.last_size = self.getSize();
            return .resize;
        }
        if (is_windows) {
            const sz = self.getSize();
            if (sz.cols != self.last_size.cols or sz.rows != self.last_size.rows) {
                self.last_size = sz;
                return .resize;
            }
        }

        // Handle ongoing bracketed paste
        if (self.in_paste) {
            return try self.readBracketedPaste();
        }

        if (self.in_buf.items.len == 0) {
            _ = try self.readMoreBytes(timeout_ms);
            if (!is_windows and g_resized.swap(false, .acquire)) {
                self.last_size = self.getSize();
                return .resize;
            }
            if (self.in_buf.items.len == 0) return .none;
        }

        // If starts with ESC and we only have 1 byte, wait briefly for escape sequence continuation
        if (self.in_buf.items[0] == 0x1b and self.in_buf.items.len == 1) {
            _ = try self.readMoreBytes(15);
        }

        const parsed = parseInput(self.in_buf.items);
        if (parsed.need_more) {
            const added = try self.readMoreBytes(20);
            if (added > 0) {
                const retry = parseInput(self.in_buf.items);
                return try self.consumeParsed(retry);
            }
            // Timed out waiting for more bytes -> treat leading ESC as plain Escape
            if (self.in_buf.items.len > 0 and self.in_buf.items[0] == 0x1b) {
                self.consumeBytes(1);
                return .{ .key = .{ .code = .escape } };
            }
            return .none;
        }

        return try self.consumeParsed(parsed);
    }

    fn consumeParsed(self: *Terminal, parsed: ParseResult) !Event {
        if (parsed.paste_start) {
            self.consumeBytes(parsed.consumed);
            self.in_paste = true;
            self.paste_buf.clearRetainingCapacity();
            return try self.readBracketedPaste();
        }
        if (parsed.consumed > 0) {
            self.consumeBytes(parsed.consumed);
        }
        return parsed.event;
    }

    fn readBracketedPaste(self: *Terminal) !Event {
        const end_marker = "\x1b[201~";
        var attempts: usize = 0;
        while (attempts < 200) : (attempts += 1) {
            if (std.mem.indexOf(u8, self.in_buf.items, end_marker)) |idx| {
                try self.paste_buf.appendSlice(self.in_buf.items[0..idx]);
                self.consumeBytes(idx + end_marker.len);
                self.in_paste = false;
                return .{ .paste = self.paste_buf.items };
            }
            // Flush safe prefix that cannot be part of end_marker
            if (self.in_buf.items.len > end_marker.len) {
                const safe = self.in_buf.items.len - end_marker.len;
                try self.paste_buf.appendSlice(self.in_buf.items[0..safe]);
                self.consumeBytes(safe);
            }
            const n = try self.readMoreBytes(50);
            if (n == 0 and self.in_buf.items.len == 0) break;
        }
        // Fallback if paste end marker never arrived
        try self.paste_buf.appendSlice(self.in_buf.items);
        self.in_buf.clearRetainingCapacity();
        self.in_paste = false;
        return .{ .paste = self.paste_buf.items };
    }

    fn consumeBytes(self: *Terminal, n: usize) void {
        if (n >= self.in_buf.items.len) {
            self.in_buf.clearRetainingCapacity();
        } else {
            const rem = self.in_buf.items.len - n;
            std.mem.copyForwards(u8, self.in_buf.items[0..rem], self.in_buf.items[n..]);
            self.in_buf.shrinkRetainingCapacity(rem);
        }
    }
};

const ParseResult = struct {
    event: Event = .none,
    consumed: usize = 0,
    need_more: bool = false,
    paste_start: bool = false,
};

pub fn parseInput(buf: []const u8) ParseResult {
    if (buf.len == 0) return .{};
    const b0 = buf[0];

    // Escape sequence
    if (b0 == 0x1b) {
        if (buf.len == 1) {
            return .{ .event = .{ .key = .{ .code = .escape } }, .consumed = 1 };
        }
        const b1 = buf[1];
        if (b1 == '[') {
            return parseCsi(buf);
        }
        if (b1 == 'O') {
            return parseSs3(buf);
        }
        // Alt + Ctrl or Alt + char
        if (b1 == 0x1b) {
            return .{ .event = .{ .key = .{ .code = .escape } }, .consumed = 1 };
        }
        if (b1 == 0x7f or b1 == 0x08) {
            return .{ .event = .{ .key = .{ .code = .backspace, .alt = true } }, .consumed = 2 };
        }
        if (b1 == '\r' or b1 == '\n') {
            return .{ .event = .{ .key = .{ .code = .enter, .alt = true } }, .consumed = 2 };
        }
        if (b1 >= 1 and b1 <= 26) {
            return .{
                .event = .{ .key = .{ .code = .{ .char = 'a' + (b1 - 1) }, .ctrl = true, .alt = true } },
                .consumed = 2,
            };
        }
        if (b1 >= 0x20 and b1 < 0x7f) {
            return .{
                .event = .{ .key = .{ .code = .{ .char = b1 }, .alt = true } },
                .consumed = 2,
            };
        }
        return .{ .event = .{ .key = .{ .code = .escape } }, .consumed = 1 };
    }

    // Control characters
    switch (b0) {
        '\r', '\n' => return .{ .event = .{ .key = .{ .code = .enter } }, .consumed = 1 },
        '\t' => return .{ .event = .{ .key = .{ .code = .tab } }, .consumed = 1 },
        0x7f => return .{ .event = .{ .key = .{ .code = .backspace } }, .consumed = 1 },
        0x00 => return .{ .event = .{ .key = .{ .code = .{ .char = ' ' }, .ctrl = true } }, .consumed = 1 },
        1...8, 11...12, 14...26 => {
            // Ctrl+A .. Ctrl+Z (excluding Tab=9, LF=10, CR=13)
            return .{
                .event = .{ .key = .{ .code = .{ .char = 'a' + (b0 - 1) }, .ctrl = true } },
                .consumed = 1,
            };
        },
        else => {},
    }

    // UTF-8 character
    const seq_len = std.unicode.utf8ByteSequenceLength(b0) catch {
        return .{ .event = .none, .consumed = 1 };
    };
    if (buf.len < seq_len) {
        return .{ .need_more = true };
    }
    const cp = std.unicode.utf8Decode(buf[0..seq_len]) catch {
        return .{ .event = .none, .consumed = 1 };
    };
    return .{
        .event = .{ .key = .{ .code = .{ .char = cp } } },
        .consumed = seq_len,
    };
}

fn parseSs3(buf: []const u8) ParseResult {
    if (buf.len < 3) return .{ .need_more = true };
    const code: KeyCode = switch (buf[2]) {
        'A' => .up,
        'B' => .down,
        'C' => .right,
        'D' => .left,
        'H' => .home,
        'F' => .end,
        'P' => .f1,
        'Q' => .f2,
        'R' => .f3,
        'S' => .f4,
        else => return .{ .event = .none, .consumed = 3 },
    };
    return .{ .event = .{ .key = .{ .code = code } }, .consumed = 3 };
}

fn parseCsi(buf: []const u8) ParseResult {
    if (buf.len < 3) return .{ .need_more = true };

    // SGR mouse: ESC [ < btn ; x ; y M/m
    if (buf[2] == '<') {
        return parseSgrMouse(buf);
    }

    // Find CSI final byte (0x40..0x7E)
    var i: usize = 2;
    while (i < buf.len and i < 32) : (i += 1) {
        if (buf[i] >= 0x40 and buf[i] <= 0x7E) break;
    }
    if (i >= buf.len) {
        if (buf.len >= 32) return .{ .event = .none, .consumed = 2 };
        return .{ .need_more = true };
    }

    const params = buf[2..i];
    const final = buf[i];
    const consumed = i + 1;

    // Bracketed paste start: ESC [ 200 ~
    if (final == '~' and std.mem.eql(u8, params, "200")) {
        return .{ .consumed = consumed, .paste_start = true };
    }

    // Shift+Tab: ESC [ Z
    if (final == 'Z' and params.len == 0) {
        return .{ .event = .{ .key = .{ .code = .tab, .shift = true } }, .consumed = consumed };
    }

    // Parse semicolon-separated numeric parameters
    var nums: [4]u32 = .{ 0, 0, 0, 0 };
    var num_count: usize = 0;
    if (params.len > 0) {
        var it = std.mem.splitScalar(u8, params, ';');
        while (it.next()) |part| {
            if (num_count >= 4) break;
            // Strip sub-params after ':' (Kitty protocol)
            const main_part = if (std.mem.indexOfScalar(u8, part, ':')) |colon| part[0..colon] else part;
            nums[num_count] = std.fmt.parseInt(u32, main_part, 10) catch 0;
            num_count += 1;
        }
    }

    // Decode xterm modifier parameter (1 + bitmask: shift=1, alt=2, ctrl=4)
    const mod_param: u32 = if (num_count >= 2) nums[1] else 1;
    const mod_bits: u32 = if (mod_param > 0) mod_param - 1 else 0;
    const shift = (mod_bits & 1) != 0;
    const alt = (mod_bits & 2) != 0;
    const ctrl = (mod_bits & 4) != 0;

    // Kitty / CSI u: ESC [ code ; mod u
    if (final == 'u' and num_count >= 1) {
        const cp = nums[0];
        const code: KeyCode = switch (cp) {
            9 => .tab,
            13 => .enter,
            27 => .escape,
            127 => .backspace,
            else => if (cp <= 0x10FFFF) .{ .char = @intCast(cp) } else return .{ .event = .none, .consumed = consumed },
        };
        return .{
            .event = .{ .key = .{ .code = code, .ctrl = ctrl, .alt = alt, .shift = shift } },
            .consumed = consumed,
        };
    }

    // xterm modifyOtherKeys: ESC [ 27 ; mod ; code ~
    if (final == '~' and num_count >= 3 and nums[0] == 27) {
        const cp = nums[2];
        const code: KeyCode = switch (cp) {
            9 => .tab,
            13 => .enter,
            27 => .escape,
            127 => .backspace,
            else => if (cp <= 0x10FFFF) .{ .char = @intCast(cp) } else return .{ .event = .none, .consumed = consumed },
        };
        return .{
            .event = .{ .key = .{ .code = code, .ctrl = ctrl, .alt = alt, .shift = shift } },
            .consumed = consumed,
        };
    }

    // Standard CSI letter keys
    const letter_code: ?KeyCode = switch (final) {
        'A' => .up,
        'B' => .down,
        'C' => .right,
        'D' => .left,
        'H' => .home,
        'F' => .end,
        'P' => .f1,
        'Q' => .f2,
        'R' => .f3,
        'S' => .f4,
        else => null,
    };
    if (letter_code) |code| {
        return .{
            .event = .{ .key = .{ .code = code, .ctrl = ctrl, .alt = alt, .shift = shift } },
            .consumed = consumed,
        };
    }

    // Standard tilde keys: ESC [ num (; mod) ~
    if (final == '~' and num_count >= 1) {
        const tilde_code: ?KeyCode = switch (nums[0]) {
            1, 7 => .home,
            3 => .delete,
            4, 8 => .end,
            5 => .page_up,
            6 => .page_down,
            11 => .f1,
            12 => .f2,
            13 => .f3,
            14 => .f4,
            15 => .f5,
            17 => .f6,
            18 => .f7,
            19 => .f8,
            20 => .f9,
            21 => .f10,
            23 => .f11,
            24 => .f12,
            else => null,
        };
        if (tilde_code) |code| {
            return .{
                .event = .{ .key = .{ .code = code, .ctrl = ctrl, .alt = alt, .shift = shift } },
                .consumed = consumed,
            };
        }
    }

    return .{ .event = .none, .consumed = consumed };
}

fn parseSgrMouse(buf: []const u8) ParseResult {
    var i: usize = 3;
    while (i < buf.len and i < 32) : (i += 1) {
        if (buf[i] == 'M' or buf[i] == 'm') break;
    }
    if (i >= buf.len) {
        if (buf.len >= 32) return .{ .event = .none, .consumed = 3 };
        return .{ .need_more = true };
    }
    const is_release = (buf[i] == 'm');
    const body = buf[3..i];
    const consumed = i + 1;

    var it = std.mem.splitScalar(u8, body, ';');
    const b_str = it.next() orelse return .{ .consumed = consumed };
    const x_str = it.next() orelse return .{ .consumed = consumed };
    const y_str = it.next() orelse return .{ .consumed = consumed };

    const cb = std.fmt.parseInt(u32, b_str, 10) catch return .{ .consumed = consumed };
    const cx = std.fmt.parseInt(usize, x_str, 10) catch return .{ .consumed = consumed };
    const cy = std.fmt.parseInt(usize, y_str, 10) catch return .{ .consumed = consumed };

    const x = if (cx > 0) cx - 1 else 0;
    const y = if (cy > 0) cy - 1 else 0;

    if ((cb & 64) != 0) {
        const kind: MouseKind = if ((cb & 1) == 0) .scroll_up else .scroll_down;
        return .{ .event = .{ .mouse = .{ .kind = kind, .button = 0, .x = x, .y = y } }, .consumed = consumed };
    }

    const button: u8 = @intCast(cb & 3);
    const is_drag = (cb & 32) != 0;
    const kind: MouseKind = if (is_release) .release else if (is_drag) .drag else .press;
    return .{ .event = .{ .mouse = .{ .kind = kind, .button = button, .x = x, .y = y } }, .consumed = consumed };
}

test "Terminal input parsing for keys, modifiers, and SGR mouse" {
    const r1 = parseInput("\x1b[1;5C");
    try std.testing.expectEqual(@as(usize, 6), r1.consumed);
    try std.testing.expect(r1.event.key.ctrl);
    try std.testing.expectEqual(KeyCode.right, r1.event.key.code);

    const r2 = parseInput("\x1b[1;6A");
    try std.testing.expect(r2.event.key.ctrl and r2.event.key.shift);
    try std.testing.expectEqual(KeyCode.up, r2.event.key.code);

    const r3 = parseInput("\x1b[<0;15;8M");
    try std.testing.expectEqual(MouseKind.press, r3.event.mouse.kind);
    try std.testing.expectEqual(@as(usize, 14), r3.event.mouse.x);
    try std.testing.expectEqual(@as(usize, 7), r3.event.mouse.y);

    const r4 = parseInput("\x13"); // Ctrl+S
    try std.testing.expect(r4.event.key.ctrl);
    try std.testing.expectEqual(KeyCode{ .char = 's' }, r4.event.key.code);

    const r5 = parseInput("\x08"); // Ctrl+H
    try std.testing.expect(r5.event.key.ctrl);
    try std.testing.expectEqual(KeyCode{ .char = 'h' }, r5.event.key.code);
}
