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
    const WCHAR = u16;

    const COORD = extern struct { X: SHORT, Y: SHORT };
    const SMALL_RECT = extern struct { Left: SHORT, Top: SHORT, Right: SHORT, Bottom: SHORT };
    const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
        dwSize: COORD,
        dwCursorPosition: COORD,
        wAttributes: WORD,
        srWindow: SMALL_RECT,
        dwMaximumWindowSize: COORD,
    };

    const KEY_EVENT: WORD = 0x0001;
    const MOUSE_EVENT: WORD = 0x0002;
    const WINDOW_BUFFER_SIZE_EVENT: WORD = 0x0004;

    const MOUSE_MOVED: DWORD = 0x0001;
    const MOUSE_WHEELED: DWORD = 0x0004;

    const RIGHT_ALT_PRESSED: DWORD = 0x0001;
    const LEFT_ALT_PRESSED: DWORD = 0x0002;
    const RIGHT_CTRL_PRESSED: DWORD = 0x0004;
    const LEFT_CTRL_PRESSED: DWORD = 0x0008;
    const SHIFT_PRESSED: DWORD = 0x0010;

    const KEY_EVENT_RECORD = extern struct {
        bKeyDown: BOOL,
        wRepeatCount: WORD,
        wVirtualKeyCode: WORD,
        wVirtualScanCode: WORD,
        uChar: extern union {
            UnicodeChar: WCHAR,
            AsciiChar: u8,
        },
        dwControlKeyState: DWORD,
    };

    const MOUSE_EVENT_RECORD = extern struct {
        dwMousePosition: COORD,
        dwButtonState: DWORD,
        dwControlKeyState: DWORD,
        dwEventFlags: DWORD,
    };

    const WINDOW_BUFFER_SIZE_RECORD = extern struct {
        dwSize: COORD,
    };

    const INPUT_RECORD = extern struct {
        EventType: WORD,
        _pad: WORD = 0,
        Event: extern union {
            KeyEvent: KEY_EVENT_RECORD,
            MouseEvent: MOUSE_EVENT_RECORD,
            WindowBufferSizeEvent: WINDOW_BUFFER_SIZE_RECORD,
            _raw: [16]u8,
        },
    };

    const CONSOLE_FONT_INFOEX = extern struct {
        cbSize: w.ULONG = @sizeOf(CONSOLE_FONT_INFOEX),
        nFont: DWORD = 0,
        dwFontSize: COORD = .{ .X = 0, .Y = 16 },
        FontFamily: w.UINT = 54, // FF_MODERN | FIXED_PITCH | TMPF_TRUETYPE
        FontWeight: w.UINT = 400, // FW_NORMAL
        FaceName: [32]WCHAR = [_]WCHAR{0} ** 32,
    };

    const LOGFONTW = extern struct {
        lfHeight: i32 = 0,
        lfWidth: i32 = 0,
        lfEscapement: i32 = 0,
        lfOrientation: i32 = 0,
        lfWeight: i32 = 400,
        lfItalic: u8 = 0,
        lfUnderline: u8 = 0,
        lfStrikeOut: u8 = 0,
        lfCharSet: u8 = 1, // DEFAULT_CHARSET
        lfOutPrecision: u8 = 0,
        lfClipPrecision: u8 = 0,
        lfQuality: u8 = 0,
        lfPitchAndFamily: u8 = 0,
        lfFaceName: [32]WCHAR = [_]WCHAR{0} ** 32,
    };

    const ENUMLOGFONTEXW = extern struct {
        elfLogFont: LOGFONTW,
        elfFullName: [64]WCHAR,
        elfStyle: [32]WCHAR,
        elfScript: [32]WCHAR,
    };

    const SIZE = extern struct {
        cx: i32,
        cy: i32,
    };

    const FIXED_PITCH: u8 = 1;
    const TRUETYPE_FONTTYPE: DWORD = 0x0004;

    const ENABLE_PROCESSED_INPUT: DWORD = 0x0001;
    const ENABLE_LINE_INPUT: DWORD = 0x0002;
    const ENABLE_ECHO_INPUT: DWORD = 0x0004;
    const ENABLE_WINDOW_INPUT: DWORD = 0x0008;
    const ENABLE_MOUSE_INPUT: DWORD = 0x0010;
    const ENABLE_EXTENDED_FLAGS: DWORD = 0x0080;
    const ENABLE_VIRTUAL_TERMINAL_INPUT: DWORD = 0x0200;

    const ENABLE_PROCESSED_OUTPUT: DWORD = 0x0001;
    const ENABLE_VIRTUAL_TERMINAL_PROCESSING: DWORD = 0x0004;
    const DISABLE_NEWLINE_AUTO_RETURN: DWORD = 0x0008;

    const GENERIC_READ: DWORD = 0x80000000;
    const GENERIC_WRITE: DWORD = 0x40000000;
    const FILE_SHARE_READ: DWORD = 0x00000001;
    const FILE_SHARE_WRITE: DWORD = 0x00000002;
    const OPEN_EXISTING: DWORD = 3;
    const CREATE_NEW_CONSOLE: DWORD = 0x00000010;

    const STARTUPINFOW = extern struct {
        cb: DWORD = @sizeOf(STARTUPINFOW),
        lpReserved: ?[*:0]WCHAR = null,
        lpDesktop: ?[*:0]WCHAR = null,
        lpTitle: ?[*:0]WCHAR = null,
        dwX: DWORD = 0,
        dwY: DWORD = 0,
        dwXSize: DWORD = 0,
        dwYSize: DWORD = 0,
        dwXCountChars: DWORD = 0,
        dwYCountChars: DWORD = 0,
        dwFillAttribute: DWORD = 0,
        dwFlags: DWORD = 0,
        wShowWindow: WORD = 0,
        cbReserved2: WORD = 0,
        lpReserved2: ?*u8 = null,
        hStdInput: ?HANDLE = null,
        hStdOutput: ?HANDLE = null,
        hStdError: ?HANDLE = null,
    };

    const PROCESS_INFORMATION = extern struct {
        hProcess: HANDLE,
        hThread: HANDLE,
        dwProcessId: DWORD,
        dwThreadId: DWORD,
    };

    const FONTENUMPROCW = *const fn (lpelfe: *const ENUMLOGFONTEXW, lpntme: *const anyopaque, FontType: DWORD, lParam: isize) callconv(w.WINAPI) c_int;

    extern "kernel32" fn CreateFileW(
        lpFileName: [*:0]const WCHAR,
        dwDesiredAccess: DWORD,
        dwShareMode: DWORD,
        lpSecurityAttributes: ?*anyopaque,
        dwCreationDisposition: DWORD,
        dwFlagsAndAttributes: DWORD,
        hTemplateFile: ?HANDLE,
    ) callconv(w.WINAPI) HANDLE;
    extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn GetEnvironmentVariableW(lpName: [*:0]const WCHAR, lpBuffer: [*]WCHAR, nSize: DWORD) callconv(w.WINAPI) DWORD;
    extern "kernel32" fn SetEnvironmentVariableW(lpName: [*:0]const WCHAR, lpValue: ?[*:0]const WCHAR) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn GetConsoleWindow() callconv(w.WINAPI) ?HANDLE;
    extern "kernel32" fn SetConsoleTitleW(lpConsoleTitle: [*:0]const WCHAR) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn CreateProcessW(
        lpApplicationName: ?[*:0]const WCHAR,
        lpCommandLine: [*:0]WCHAR,
        lpProcessAttributes: ?*anyopaque,
        lpThreadAttributes: ?*anyopaque,
        bInheritHandles: BOOL,
        dwCreationFlags: DWORD,
        lpEnvironment: ?*anyopaque,
        lpCurrentDirectory: ?[*:0]const WCHAR,
        lpStartupInfo: *STARTUPINFOW,
        lpProcessInformation: *PROCESS_INFORMATION,
    ) callconv(w.WINAPI) BOOL;
    extern "user32" fn IsWindowVisible(hWnd: HANDLE) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn GetConsoleMode(hConsoleHandle: HANDLE, lpMode: *DWORD) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn SetConsoleMode(hConsoleHandle: HANDLE, dwMode: DWORD) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn GetConsoleScreenBufferInfo(hConsoleOutput: HANDLE, lpConsoleScreenBufferInfo: *CONSOLE_SCREEN_BUFFER_INFO) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn GetNumberOfConsoleInputEvents(hConsoleInput: HANDLE, lpcNumberOfEvents: *DWORD) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn ReadConsoleInputW(hConsoleInput: HANDLE, lpBuffer: [*]INPUT_RECORD, nLength: DWORD, lpNumberOfEventsRead: *DWORD) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD) callconv(w.WINAPI) DWORD;
    extern "kernel32" fn SetConsoleOutputCP(wCodePageID: w.UINT) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn SetConsoleCP(wCodePageID: w.UINT) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn GetCurrentConsoleFontEx(hConsoleOutput: HANDLE, bMaximumWindow: BOOL, lpConsoleCurrentFontEx: *CONSOLE_FONT_INFOEX) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn SetCurrentConsoleFontEx(hConsoleOutput: HANDLE, bMaximumWindow: BOOL, lpConsoleCurrentFontEx: *const CONSOLE_FONT_INFOEX) callconv(w.WINAPI) BOOL;
    extern "kernel32" fn WriteConsoleW(hConsoleOutput: HANDLE, lpBuffer: [*]const WCHAR, nNumberOfCharsToWrite: DWORD, lpNumberOfCharsWritten: *DWORD, lpReserved: ?*anyopaque) callconv(w.WINAPI) BOOL;

    extern "gdi32" fn CreateCompatibleDC(hdc: ?HANDLE) callconv(w.WINAPI) ?HANDLE;
    extern "gdi32" fn DeleteDC(hdc: HANDLE) callconv(w.WINAPI) BOOL;
    extern "gdi32" fn EnumFontFamiliesExW(hdc: HANDLE, lpLogfont: *LOGFONTW, lpProc: FONTENUMPROCW, lParam: isize, dwFlags: DWORD) callconv(w.WINAPI) c_int;
    extern "gdi32" fn CreateFontIndirectW(lplf: *const LOGFONTW) callconv(w.WINAPI) ?HANDLE;
    extern "gdi32" fn SelectObject(hdc: HANDLE, h: HANDLE) callconv(w.WINAPI) ?HANDLE;
    extern "gdi32" fn DeleteObject(ho: HANDLE) callconv(w.WINAPI) BOOL;
    extern "gdi32" fn GetTextExtentPoint32W(hdc: HANDLE, lpString: [*]const WCHAR, c: c_int, psizl: *SIZE) callconv(w.WINAPI) BOOL;
} else struct {};

pub const FontOption = struct {
    name: []const u8, // Owned UTF-8 face name (e.g. "MS Gothic", "BIZ UDGothic", "Consolas")
    win_face: []const u8, // Owned UTF-8 Win32 face name passed to SetCurrentConsoleFontEx
    is_strict_1to2: bool, // True if halfwidth:fullwidth advance ratio is strictly 1:2
};

const FallbackFontDef = struct {
    name: []const u8,
    win_face: []const u8,
    is_strict_1to2: bool,
};

const FALLBACK_FONTS = [_]FallbackFontDef{
    .{ .name = "MS Gothic", .win_face = "\xef\xbc\xad\xef\xbc\xb3 \xe3\x82\xb4\xe3\x82\xb7\xe3\x83\x83\xe3\x82\xaf", .is_strict_1to2 = true },
    .{ .name = "BIZ UDGothic", .win_face = "BIZ UDGothic", .is_strict_1to2 = true },
    .{ .name = "PlemolJP Console", .win_face = "PlemolJP Console", .is_strict_1to2 = true },
    .{ .name = "HackGen Console", .win_face = "HackGen Console", .is_strict_1to2 = true },
    .{ .name = "UDEV Gothic", .win_face = "UDEV Gothic", .is_strict_1to2 = true },
    .{ .name = "Sarasa Mono J", .win_face = "Sarasa Mono J", .is_strict_1to2 = true },
    .{ .name = "MyricaM M", .win_face = "MyricaM M", .is_strict_1to2 = true },
    .{ .name = "Ricty Diminished", .win_face = "Ricty Diminished", .is_strict_1to2 = true },
    .{ .name = "Cascadia Mono", .win_face = "Cascadia Mono", .is_strict_1to2 = false },
    .{ .name = "Consolas", .win_face = "Consolas", .is_strict_1to2 = false },
    .{ .name = "Courier New", .win_face = "Courier New", .is_strict_1to2 = false },
    .{ .name = "Lucida Console", .win_face = "Lucida Console", .is_strict_1to2 = false },
};

const WinFontEnumCtx = if (is_windows) struct {
    term: *Terminal,
    dc: win32.HANDLE,

    fn callback(lpelfe: *const win32.ENUMLOGFONTEXW, _: *const anyopaque, font_type: win32.DWORD, lparam: isize) callconv(std.os.windows.WINAPI) c_int {
        const ctx: *WinFontEnumCtx = @ptrFromInt(@as(usize, @bitCast(lparam)));
        const lf = &lpelfe.elfLogFont;

        // Only allow TrueType/OpenType monospace (FIXED_PITCH) fonts
        if ((font_type & win32.TRUETYPE_FONTTYPE) == 0) return 1;
        if ((lf.lfPitchAndFamily & 0x03) != win32.FIXED_PITCH) return 1;

        // Find length of null-terminated UTF-16 face name
        var wlen: usize = 0;
        while (wlen < lf.lfFaceName.len and lf.lfFaceName[wlen] != 0) : (wlen += 1) {}
        if (wlen == 0) return 1;

        // Exclude vertical fonts starting with '@'
        if (lf.lfFaceName[0] == '@') return 1;

        var utf8_buf: [128]u8 = undefined;
        const utf8_len = std.unicode.utf16LeToUtf8(&utf8_buf, lf.lfFaceName[0..wlen]) catch return 1;
        const face_utf8 = utf8_buf[0..utf8_len];

        // Exclude symbol/icon fonts that cannot render text in a console
        if (std.mem.indexOf(u8, face_utf8, "Marlett") != null or
            std.mem.indexOf(u8, face_utf8, "Wingdings") != null or
            std.mem.indexOf(u8, face_utf8, "Webdings") != null or
            std.mem.indexOf(u8, face_utf8, "Symbol") != null)
        {
            return 1;
        }

        // Deduplicate
        for (ctx.term.fonts.items) |existing| {
            if (std.ascii.eqlIgnoreCase(existing.name, face_utf8) or std.mem.eql(u8, existing.win_face, face_utf8)) {
                return 1;
            }
        }

        // Measure actual halfwidth ('A', 'M', 'i') and fullwidth ('あ', '漢') glyph widths in GDI
        var test_lf = lf.*;
        test_lf.lfHeight = -24;
        test_lf.lfWidth = 0;
        var is_strict_1to2 = false;
        var is_true_monospace = true;

        if (win32.CreateFontIndirectW(&test_lf)) |hfont| {
            defer _ = win32.DeleteObject(hfont);
            const old_obj = win32.SelectObject(ctx.dc, hfont);
            defer if (old_obj) |o| {
                _ = win32.SelectObject(ctx.dc, o);
            };

            const ch_i = [1]u16{'i'};
            const ch_M = [1]u16{'M'};
            const ch_A = [1]u16{'A'};
            const ch_a_jp = [1]u16{0x3042}; // 'あ'
            const ch_kanji = [1]u16{0x6F22}; // '漢'
            var sz_i = win32.SIZE{ .cx = 0, .cy = 0 };
            var sz_M = win32.SIZE{ .cx = 0, .cy = 0 };
            var sz_A = win32.SIZE{ .cx = 0, .cy = 0 };
            var sz_jp = win32.SIZE{ .cx = 0, .cy = 0 };
            var sz_kanji = win32.SIZE{ .cx = 0, .cy = 0 };

            if (win32.GetTextExtentPoint32W(ctx.dc, &ch_i, 1, &sz_i) != 0 and
                win32.GetTextExtentPoint32W(ctx.dc, &ch_M, 1, &sz_M) != 0 and
                win32.GetTextExtentPoint32W(ctx.dc, &ch_A, 1, &sz_A) != 0 and
                win32.GetTextExtentPoint32W(ctx.dc, &ch_a_jp, 1, &sz_jp) != 0 and
                win32.GetTextExtentPoint32W(ctx.dc, &ch_kanji, 1, &sz_kanji) != 0)
            {
                if (sz_i.cx <= 0 or sz_i.cx != sz_M.cx or sz_A.cx != sz_M.cx) {
                    is_true_monospace = false;
                } else if (sz_jp.cx == sz_A.cx * 2 and sz_kanji.cx == sz_A.cx * 2) {
                    // Check if font actually supports Japanese charset (SHIFTJIS_CHARSET=128) or is a known CJK 1:2 font
                    is_strict_1to2 = (lf.lfCharSet == 128) or isKnown1To2FontName(face_utf8);
                }
            }
        }

        if (!is_true_monospace) return 1;
        if (isKnown1To2FontName(face_utf8)) is_strict_1to2 = true;

        // Friendly label for fullwidth Japanese MS Gothic name ("ＭＳ ゴシック")
        const display_name = if (std.mem.eql(u8, face_utf8, "\xef\xbc\xad\xef\xbc\xb3 \xe3\x82\xb4\xe3\x82\xb7\xe3\x83\x83\xe3\x82\xaf"))
            "MS Gothic (\xef\xbc\xad\xef\xbc\xb3 \xe3\x82\xb4\xe3\x82\xb7\xe3\x83\x83\xe3\x82\xaf)"
        else
            face_utf8;

        ctx.term.addFontOption(display_name, face_utf8, is_strict_1to2) catch {};
        return 1;
    }
} else struct {};

fn isKnown1To2FontName(name: []const u8) bool {
    const known = [_][]const u8{
        "\xef\xbc\xad\xef\xbc\xb3 \xe3\x82\xb4\xe3\x82\xb7\xe3\x83\x83\xe3\x82\xaf", // ＭＳ ゴシック
        "MS Gothic",
        "BIZ UDGothic",
        "PlemolJP",
        "HackGen",
        "UDEV Gothic",
        "Sarasa Mono",
        "Myrica",
        "Ricty",
        "Cica",
        "Moralerspace",
        "VL Gothic",
        "IPAGothic",
        "Noto Sans Mono CJK",
        "Source Han Code JP",
    };
    for (known) |k| {
        if (std.mem.indexOf(u8, name, k) != null) return true;
    }
    return false;
}

const Win32Gui = @import("win32_gui.zig").Win32Gui;

pub var g_force_console_mode: bool = false;

pub const Terminal = struct {
    allocator: std.mem.Allocator,
    stdin_file: std.fs.File,
    stdout_file: std.fs.File,
    raw_enabled: bool,

    orig_termios: if (!is_windows) std.posix.termios else void,
    orig_in_mode: if (is_windows) std.os.windows.DWORD else void,
    orig_out_mode: if (is_windows) std.os.windows.DWORD else void,
    orig_font: if (is_windows) win32.CONSOLE_FONT_INFOEX else void,
    has_orig_font: if (is_windows) bool else void,
    win_utf16_high: if (is_windows) ?u16 else void,
    win_gui: if (is_windows) ?*Win32Gui else void,

    fonts: std.ArrayList(FontOption),
    font_preset_idx: usize,
    font_height: i16,
    active_font_name: []const u8,
    active_font_is_1to2: bool,
    console_font_changeable: bool,

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
            .orig_font = if (is_windows) .{} else {},
            .has_orig_font = if (is_windows) false else {},
            .win_utf16_high = if (is_windows) null else {},
            .win_gui = if (is_windows) null else {},
            .fonts = std.ArrayList(FontOption).init(allocator),
            .font_preset_idx = 0,
            .font_height = 18,
            .active_font_name = "MS Gothic",
            .active_font_is_1to2 = true,
            .console_font_changeable = true,
            .last_size = .{ .cols = 80, .rows = 24 },
            .in_buf = std.ArrayList(u8).init(allocator),
            .paste_buf = std.ArrayList(u8).init(allocator),
            .in_paste = false,
        };
        errdefer term.freeFonts();
        try term.discoverMonospaceFonts();
        try term.enableRawMode();
        term.last_size = term.getSize();
        return term;
    }

    fn freeFonts(self: *Terminal) void {
        for (self.fonts.items) |f| {
            self.allocator.free(f.name);
            self.allocator.free(f.win_face);
        }
        self.fonts.deinit();
    }

    pub fn addFontOption(self: *Terminal, name: []const u8, win_face: []const u8, is_strict_1to2: bool) !void {
        const dup_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(dup_name);
        const dup_face = try self.allocator.dupe(u8, win_face);
        errdefer self.allocator.free(dup_face);
        try self.fonts.append(.{
            .name = dup_name,
            .win_face = dup_face,
            .is_strict_1to2 = is_strict_1to2,
        });
    }

    fn discoverMonospaceFonts(self: *Terminal) !void {
        if (is_windows) {
            if (win32.CreateCompatibleDC(null)) |dc| {
                defer _ = win32.DeleteDC(dc);
                var lf = win32.LOGFONTW{
                    .lfCharSet = 1, // DEFAULT_CHARSET
                };
                var ctx = WinFontEnumCtx{ .term = self, .dc = dc };
                _ = win32.EnumFontFamiliesExW(dc, &lf, WinFontEnumCtx.callback, @bitCast(@intFromPtr(&ctx)), 0);
            }
        }

        // If enumeration found nothing (e.g. non-Windows or headless), populate fallback monospace fonts
        if (self.fonts.items.len == 0) {
            for (FALLBACK_FONTS) |fb| {
                try self.addFontOption(fb.name, fb.win_face, fb.is_strict_1to2);
            }
        }

        // Sort fonts so strict 1:2 CJK monospace fonts come first (with MS Gothic / BIZ UDGothic at the very top),
        // followed by non-1:2 monospace fonts in alphabetical order.
        std.mem.sort(FontOption, self.fonts.items, {}, struct {
            fn lessThan(_: void, a: FontOption, b: FontOption) bool {
                if (a.is_strict_1to2 != b.is_strict_1to2) {
                    return a.is_strict_1to2; // 1:2 fonts first
                }
                const pa = priorityRank(a.win_face);
                const pb = priorityRank(b.win_face);
                if (pa != pb) return pa < pb;
                return std.ascii.lessThanIgnoreCase(a.name, b.name);
            }

            fn priorityRank(face: []const u8) usize {
                if (std.mem.indexOf(u8, face, "\xef\xbc\xad\xef\xbc\xb3 \xe3\x82\xb4\xe3\x82\xb7\xe3\x83\x83\xe3\x82\xaf") != null or
                    std.ascii.eqlIgnoreCase(face, "MS Gothic")) return 0;
                if (std.mem.indexOf(u8, face, "BIZ UDGothic") != null) return 1;
                if (std.mem.indexOf(u8, face, "PlemolJP") != null) return 2;
                if (std.mem.indexOf(u8, face, "HackGen") != null) return 3;
                if (std.mem.indexOf(u8, face, "UDEV Gothic") != null) return 4;
                if (std.mem.indexOf(u8, face, "Cascadia Mono") != null) return 10;
                if (std.mem.indexOf(u8, face, "Consolas") != null) return 11;
                return 5;
            }
        }.lessThan);
    }

    pub fn deinit(self: *Terminal) void {
        self.disableRawMode();
        self.freeFonts();
        self.in_buf.deinit();
        self.paste_buf.deinit();
    }

    fn openConOutHandle(self: *const Terminal) struct { handle: if (is_windows) win32.HANDLE else void, need_close: bool } {
        if (is_windows) {
            const conout_w = [_:0]u16{ 'C', 'O', 'N', 'O', 'U', 'T', '$' };
            const h = win32.CreateFileW(
                &conout_w,
                win32.GENERIC_READ | win32.GENERIC_WRITE,
                win32.FILE_SHARE_READ | win32.FILE_SHARE_WRITE,
                null,
                win32.OPEN_EXISTING,
                0,
                null,
            );
            if (h != std.os.windows.INVALID_HANDLE_VALUE) {
                return .{ .handle = h, .need_close = true };
            }
            return .{ .handle = self.stdout_file.handle, .need_close = false };
        }
        return .{ .handle = {}, .need_close = false };
    }

    fn isUnderWindowsTerminal() bool {
        if (is_windows) {
            const conhost_flag = [_:0]u16{ 'Z', 'E', 'D', 'I', 'T', '_', 'I', 'N', '_', 'C', 'O', 'N', 'H', 'O', 'S', 'T' };
            var fbuf: [8]u16 = undefined;
            if (win32.GetEnvironmentVariableW(&conhost_flag, &fbuf, fbuf.len) > 0) {
                return false;
            }
            const wt_var = [_:0]u16{ 'W', 'T', '_', 'S', 'E', 'S', 'S', 'I', 'O', 'N' };
            var buf: [8]u16 = undefined;
            if (win32.GetEnvironmentVariableW(&wt_var, &buf, buf.len) > 0) {
                return true;
            }
            if (win32.GetConsoleWindow()) |hwnd| {
                if (win32.IsWindowVisible(hwnd) == 0) {
                    return true;
                }
            } else {
                return true;
            }
            return false;
        }
        return false;
    }

    pub fn maybeRelaunchInConhost(allocator: std.mem.Allocator, raw_args: []const []const u8) bool {
        if (!is_windows) return false;
        // Only relaunch in conhost.exe when user explicitly asks for console mode (--console / --conhost)
        // because default mode on Windows opens our native Win32 GDI window!
        if (!g_force_console_mode) return false;

        const conhost_flag = [_:0]u16{ 'Z', 'E', 'D', 'I', 'T', '_', 'I', 'N', '_', 'C', 'O', 'N', 'H', 'O', 'S', 'T' };
        var fbuf: [8]u16 = undefined;
        if (win32.GetEnvironmentVariableW(&conhost_flag, &fbuf, fbuf.len) > 0) {
            const wt_var = [_:0]u16{ 'W', 'T', '_', 'S', 'E', 'S', 'S', 'I', 'O', 'N' };
            _ = win32.SetEnvironmentVariableW(&wt_var, null);
            return false;
        }

        for (raw_args[1..]) |a| {
            if (std.mem.eql(u8, a, "--no-conhost") or std.mem.eql(u8, a, "--wt")) {
                return false;
            }
        }

        if (!isUnderWindowsTerminal()) return false;

        const one_w = [_:0]u16{'1'};
        _ = win32.SetEnvironmentVariableW(&conhost_flag, &one_w);

        const exe_path = std.fs.selfExePathAlloc(allocator) catch return false;
        defer allocator.free(exe_path);

        var sysroot_w: [260]u16 = undefined;
        const sr_name = [_:0]u16{ 'S', 'y', 's', 't', 'e', 'm', 'R', 'o', 'o', 't' };
        const sr_len = win32.GetEnvironmentVariableW(&sr_name, &sysroot_w, sysroot_w.len);
        var sysroot_utf8_buf: [260]u8 = undefined;
        const sysroot_utf8: []const u8 = if (sr_len > 0 and sr_len < sysroot_w.len)
            sysroot_utf8_buf[0..(std.unicode.utf16LeToUtf8(&sysroot_utf8_buf, sysroot_w[0..sr_len]) catch 0)]
        else
            "C:\\Windows";
        const root_str = if (sysroot_utf8.len > 0) sysroot_utf8 else "C:\\Windows";

        var cmd_utf8 = std.ArrayList(u8).init(allocator);
        defer cmd_utf8.deinit();
        cmd_utf8.writer().print("\"{s}\\System32\\conhost.exe\" \"{s}\"", .{ root_str, exe_path }) catch return false;
        for (raw_args[1..]) |a| {
            cmd_utf8.writer().print(" \"{s}\"", .{a}) catch return false;
        }

        const cmd_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, cmd_utf8.items) catch return false;
        defer allocator.free(cmd_w);

        var si = win32.STARTUPINFOW{};
        var pi: win32.PROCESS_INFORMATION = undefined;
        // Note: conhost.exe is a GUI subsystem exe; launch with dwCreationFlags = 0 so Windows 11 DefTerm does not intercept it!
        if (win32.CreateProcessW(
            null,
            cmd_w.ptr,
            null,
            null,
            0,
            0,
            null,
            null,
            &si,
            &pi,
        ) != 0) {
            _ = win32.CloseHandle(pi.hThread);
            _ = win32.CloseHandle(pi.hProcess);
            return true;
        }
        return false;
    }

    fn enableRawMode(self: *Terminal) !void {
        if (is_windows) {
            // Solution B (default on Windows): Open dedicated Win32 GDI window with 100% font control & 1:2 cell alignment!
            if (!g_force_console_mode) {
                if (self.fonts.items.len > 0) {
                    self.active_font_name = self.fonts.items[0].name;
                    self.active_font_is_1to2 = self.fonts.items[0].is_strict_1to2;
                }
                if (Win32Gui.init(self.allocator, self)) |gui| {
                    self.win_gui = gui;
                    self.raw_enabled = true;
                    self.console_font_changeable = true;
                    _ = self.applyFontPreset(0);
                    return;
                } else |_| {
                    // Fallback to console mode if GUI window creation fails (e.g. headless SSH session)
                }
            }

            // Solution A (Console Mode): Keep CodePage 932 when calling SetCurrentConsoleFontEx and use WriteConsoleW!
            const in_h = self.stdin_file.handle;
            const out_h = self.stdout_file.handle;
            _ = win32.GetConsoleMode(in_h, &self.orig_in_mode);
            _ = win32.GetConsoleMode(out_h, &self.orig_out_mode);

            const new_in: std.os.windows.DWORD = win32.ENABLE_WINDOW_INPUT |
                win32.ENABLE_MOUSE_INPUT |
                win32.ENABLE_EXTENDED_FLAGS;
            const new_out = self.orig_out_mode | win32.ENABLE_PROCESSED_OUTPUT |
                win32.ENABLE_VIRTUAL_TERMINAL_PROCESSING | win32.DISABLE_NEWLINE_AUTO_RETURN;
            _ = win32.SetConsoleMode(in_h, new_in);
            _ = win32.SetConsoleMode(out_h, new_out);

            self.raw_enabled = true;
            try self.writeAll("\x1b[?1049h\x1b[?1000h\x1b[?1002h\x1b[?1006h\x1b[?2004h\x1b[2J\x1b[H");

            const conout = self.openConOutHandle();
            defer if (conout.need_close) {
                _ = win32.CloseHandle(conout.handle);
            };
            self.orig_font.cbSize = @sizeOf(win32.CONSOLE_FONT_INFOEX);
            if (win32.GetCurrentConsoleFontEx(conout.handle, 0, &self.orig_font) != 0) {
                self.has_orig_font = true;
                if (self.orig_font.dwFontSize.Y >= 10 and self.orig_font.dwFontSize.Y <= 48) {
                    self.font_height = self.orig_font.dwFontSize.Y;
                }
            }
            _ = self.applyFontPreset(0);
            return;
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

    pub fn fontCount(self: *const Terminal) usize {
        return self.fonts.items.len;
    }

    pub fn getFontOption(self: *const Terminal, idx: usize) FontOption {
        return self.fonts.items[idx % self.fonts.items.len];
    }

    pub fn applyFontPreset(self: *Terminal, preset_idx: usize) FontOption {
        if (self.fonts.items.len == 0) {
            return .{ .name = "Default", .win_face = "Default", .is_strict_1to2 = false };
        }
        const idx = preset_idx % self.fonts.items.len;
        self.font_preset_idx = idx;
        const opt = self.fonts.items[idx];
        self.active_font_name = opt.name;
        self.active_font_is_1to2 = opt.is_strict_1to2;

        if (is_windows) {
            if (self.win_gui) |gui| {
                gui.term = self;
                gui.setFont(opt.win_face, self.font_height);
                self.console_font_changeable = true;
                return opt;
            }

            // Console mode (Solution A): set CP 932 before SetCurrentConsoleFontEx so conhost accepts Japanese fonts!
            _ = win32.SetConsoleOutputCP(932);
            const conout = self.openConOutHandle();
            defer if (conout.need_close) {
                _ = win32.CloseHandle(conout.handle);
            };
            var fi = win32.CONSOLE_FONT_INFOEX{
                .cbSize = @sizeOf(win32.CONSOLE_FONT_INFOEX),
                .nFont = 0,
                .dwFontSize = .{ .X = 0, .Y = self.font_height },
                .FontFamily = 54, // FF_MODERN | FIXED_PITCH | TMPF_TRUETYPE
                .FontWeight = 400,
                .FaceName = [_]u16{0} ** 32,
            };
            if (std.unicode.utf8ToUtf16Le(&fi.FaceName, opt.win_face)) |len| {
                if (len < fi.FaceName.len) fi.FaceName[len] = 0;
                const ok = win32.SetCurrentConsoleFontEx(conout.handle, 0, &fi) != 0;
                _ = win32.SetCurrentConsoleFontEx(self.stdout_file.handle, 0, &fi);
                var check = win32.CONSOLE_FONT_INFOEX{
                    .cbSize = @sizeOf(win32.CONSOLE_FONT_INFOEX),
                };
                if (!isUnderWindowsTerminal() and ok and win32.GetCurrentConsoleFontEx(conout.handle, 0, &check) != 0) {
                    var match = true;
                    var k: usize = 0;
                    while (k < 3 and k < len) : (k += 1) {
                        if (check.FaceName[k] != fi.FaceName[k]) {
                            match = false;
                            break;
                        }
                    }
                    self.console_font_changeable = match and (check.FaceName[0] != 0);
                } else {
                    self.console_font_changeable = false;
                }
            } else |_| {}
        }
        return opt;
    }

    pub fn cycleFontPreset(self: *Terminal) FontOption {
        return self.applyFontPreset((self.font_preset_idx + 1) % @max(self.fonts.items.len, 1));
    }

    pub fn adjustFontSize(self: *Terminal, delta: i16) i16 {
        self.font_height = std.math.clamp(self.font_height + delta, 10, 42);
        if (is_windows) {
            _ = self.applyFontPreset(self.font_preset_idx);
        }
        return self.font_height;
    }

    fn disableRawMode(self: *Terminal) void {
        if (!self.raw_enabled) return;
        self.raw_enabled = false;

        if (is_windows) {
            if (self.win_gui) |gui| {
                gui.deinit();
                self.win_gui = null;
                return;
            }
        }

        // Restore normal screen, show cursor, disable mouse & bracketed paste
        self.writeAll("\x1b[?2004l\x1b[?1006l\x1b[?1002l\x1b[?1000l\x1b[?25h\x1b[0m\x1b[?1049l") catch {};

        if (is_windows) {
            if (self.has_orig_font) {
                const conout = self.openConOutHandle();
                defer if (conout.need_close) {
                    _ = win32.CloseHandle(conout.handle);
                };
                _ = win32.SetCurrentConsoleFontEx(conout.handle, 0, &self.orig_font);
            }
            _ = win32.SetConsoleMode(self.stdin_file.handle, self.orig_in_mode);
            _ = win32.SetConsoleMode(self.stdout_file.handle, self.orig_out_mode);
        } else {
            std.posix.tcsetattr(self.stdin_file.handle, .FLUSH, self.orig_termios) catch {};
        }
    }

    pub fn writeAll(self: *Terminal, bytes: []const u8) !void {
        if (is_windows) {
            if (self.win_gui) |gui| {
                gui.writeAnsi(self, bytes);
                return;
            }
            // In Windows console mode, use WriteConsoleW (UTF-16) so we can keep CodePage 932 active
            // and still output full Unicode + ANSI VT sequences without breaking SetCurrentConsoleFontEx!
            if (std.unicode.utf8ToUtf16LeAlloc(self.allocator, bytes)) |utf16_slice| {
                defer self.allocator.free(utf16_slice);
                var offset: usize = 0;
                while (offset < utf16_slice.len) {
                    const chunk: u32 = @intCast(@min(utf16_slice.len - offset, 16384));
                    var written: win32.DWORD = 0;
                    if (win32.WriteConsoleW(self.stdout_file.handle, utf16_slice[offset..].ptr, chunk, &written, null) == 0 or written == 0) {
                        // Fallback to raw stdout write if stdout is redirected
                        try self.stdout_file.writeAll(bytes);
                        return;
                    }
                    offset += written;
                }
                return;
            } else |_| {}
        }
        try self.stdout_file.writeAll(bytes);
    }

    pub fn copyOsc52(self: *Terminal, text: []const u8) void {
        if (text.len == 0 or text.len > 65536) return;
        if (is_windows) {
            if (self.win_gui) |gui| {
                gui.setClipboard(text);
                return;
            }
        }
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
            if (self.win_gui) |gui| {
                return .{ .cols = gui.cols, .rows = gui.rows };
            }
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
            const handles = [_]std.posix.fd_t{ self.stdout_file.handle, self.stdin_file.handle };
            for (handles) |h| {
                const rc = std.posix.system.ioctl(h, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
                if (rc == 0 and ws.col > 0 and ws.row > 0) {
                    return .{ .cols = ws.col, .rows = ws.row };
                }
            }
            return .{ .cols = 80, .rows = 24 };
        }
    }

    fn checkResize(self: *Terminal) bool {
        if (is_windows) {
            if (self.win_gui) |gui| {
                gui.term = self;
                const was_resized = gui.resized;
                gui.resized = false;
                const sz = self.getSize();
                if (was_resized or sz.cols != self.last_size.cols or sz.rows != self.last_size.rows) {
                    self.last_size = sz;
                    return true;
                }
                return false;
            }
        }
        const sig = if (!is_windows) g_resized.swap(false, .acquire) else g_resized.swap(false, .acquire);
        const sz = self.getSize();
        if (sig or sz.cols != self.last_size.cols or sz.rows != self.last_size.rows) {
            self.last_size = sz;
            return true;
        }
        return false;
    }

    fn pollInput(self: *Terminal, timeout_ms: i32) bool {
        if (is_windows) {
            if (self.win_gui) |gui| {
                const before = self.in_buf.items.len;
                gui.pumpMessages(self, timeout_ms);
                return self.in_buf.items.len > before;
            }
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
        if (is_windows) {
            if (self.win_gui) |gui| {
                const before = self.in_buf.items.len;
                gui.pumpMessages(self, timeout_ms);
                return self.in_buf.items.len - before;
            }
        }
        if (!self.pollInput(timeout_ms)) return 0;
        if (is_windows) {
            var records: [64]win32.INPUT_RECORD = undefined;
            var num_read: std.os.windows.DWORD = 0;
            if (win32.ReadConsoleInputW(self.stdin_file.handle, &records, records.len, &num_read) == 0) {
                return 0;
            }
            var added: usize = 0;
            for (records[0..num_read]) |rec| {
                if (rec.EventType == win32.WINDOW_BUFFER_SIZE_EVENT) {
                    g_resized.store(true, .release);
                } else if (rec.EventType == win32.MOUSE_EVENT) {
                    const mev = rec.Event.MouseEvent;
                    const mx: usize = @intCast(@max(mev.dwMousePosition.X, 0) + 1);
                    const my: usize = @intCast(@max(mev.dwMousePosition.Y, 0) + 1);
                    var sgr_buf: [32]u8 = undefined;
                    if ((mev.dwEventFlags & win32.MOUSE_WHEELED) != 0) {
                        const delta: i16 = @bitCast(@as(u16, @truncate(mev.dwButtonState >> 16)));
                        const btn: u8 = if (delta > 0) 64 else 65;
                        const s = std.fmt.bufPrint(&sgr_buf, "\x1b[<{d};{d};{d}M", .{ btn, mx, my }) catch "";
                        try self.in_buf.appendSlice(s);
                        added += s.len;
                    } else if (mev.dwEventFlags == 0) {
                        const pressed = (mev.dwButtonState & 0x01) != 0;
                        const s = std.fmt.bufPrint(&sgr_buf, "\x1b[<0;{d};{d}{c}", .{ mx, my, if (pressed) @as(u8, 'M') else 'm' }) catch "";
                        try self.in_buf.appendSlice(s);
                        added += s.len;
                    } else if ((mev.dwEventFlags & win32.MOUSE_MOVED) != 0 and (mev.dwButtonState & 0x01) != 0) {
                        const s = std.fmt.bufPrint(&sgr_buf, "\x1b[<32;{d};{d}M", .{ mx, my }) catch "";
                        try self.in_buf.appendSlice(s);
                        added += s.len;
                    }
                } else if (rec.EventType == win32.KEY_EVENT) {
                    const kev = rec.Event.KeyEvent;
                    if (kev.bKeyDown != 0) {
                        const repeat: usize = @max(@as(usize, kev.wRepeatCount), 1);
                        var r: usize = 0;
                        while (r < repeat) : (r += 1) {
                            const vk_added = try self.appendWinVirtualKey(kev.wVirtualKeyCode, kev.dwControlKeyState);
                            if (vk_added > 0) {
                                added += vk_added;
                            } else if (kev.uChar.UnicodeChar != 0) {
                                const alt = (kev.dwControlKeyState & (win32.LEFT_ALT_PRESSED | win32.RIGHT_ALT_PRESSED)) != 0;
                                const ctrl = (kev.dwControlKeyState & (win32.LEFT_CTRL_PRESSED | win32.RIGHT_CTRL_PRESSED)) != 0;
                                if (alt and !ctrl and kev.uChar.UnicodeChar < 0x80) {
                                    try self.in_buf.append(0x1b);
                                    added += 1;
                                }
                                added += try self.appendWinUtf16Unit(kev.uChar.UnicodeChar);
                            }
                        }
                    }
                }
            }
            return added;
        } else {
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
    }

    fn appendWinUtf16Unit(self: *Terminal, unit: u16) !usize {
        if (is_windows) {
            var cp: u21 = unit;
            if (unit >= 0xD800 and unit <= 0xDBFF) {
                self.win_utf16_high = unit;
                return 0;
            } else if (unit >= 0xDC00 and unit <= 0xDFFF) {
                if (self.win_utf16_high) |hi| {
                    cp = 0x10000 + ((@as(u21, hi - 0xD800) << 10) | @as(u21, unit - 0xDC00));
                    self.win_utf16_high = null;
                } else {
                    return 0;
                }
            } else {
                self.win_utf16_high = null;
            }
            var out: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(cp, &out) catch return 0;
            try self.in_buf.appendSlice(out[0..len]);
            return len;
        }
        return 0;
    }

    fn appendWinVirtualKey(self: *Terminal, vk: u16, ctrl_state: u32) !usize {
        if (is_windows) {
            const shift = (ctrl_state & win32.SHIFT_PRESSED) != 0;
            const alt = (ctrl_state & (win32.LEFT_ALT_PRESSED | win32.RIGHT_ALT_PRESSED)) != 0;
            const ctrl = (ctrl_state & (win32.LEFT_CTRL_PRESSED | win32.RIGHT_CTRL_PRESSED)) != 0;
            const mod: u8 = 1 + (if (shift) @as(u8, 1) else 0) + (if (alt) @as(u8, 2) else 0) + (if (ctrl) @as(u8, 4) else 0);

            var buf: [16]u8 = undefined;
            const seq: []const u8 = switch (vk) {
                0x08 => if (ctrl) "\x1b[127;5u" else if (alt) "\x1b\x7f" else "\x7f", // VK_BACK
                0x09 => if (ctrl and shift) "\x1b[27;6;9~" else if (ctrl) "\x1b[27;5;9~" else if (shift) "\x1b[Z" else "\t", // VK_TAB
                0x0D => if (alt) "\x1b\r" else "\r", // VK_RETURN
                0x1B => "\x1b", // VK_ESCAPE
                0x26 => if (mod == 1) "\x1b[A" else std.fmt.bufPrint(&buf, "\x1b[1;{d}A", .{mod}) catch "", // VK_UP
                0x28 => if (mod == 1) "\x1b[B" else std.fmt.bufPrint(&buf, "\x1b[1;{d}B", .{mod}) catch "", // VK_DOWN
                0x27 => if (mod == 1) "\x1b[C" else std.fmt.bufPrint(&buf, "\x1b[1;{d}C", .{mod}) catch "", // VK_RIGHT
                0x25 => if (mod == 1) "\x1b[D" else std.fmt.bufPrint(&buf, "\x1b[1;{d}D", .{mod}) catch "", // VK_LEFT
                0x24 => if (mod == 1) "\x1b[H" else std.fmt.bufPrint(&buf, "\x1b[1;{d}H", .{mod}) catch "", // VK_HOME
                0x23 => if (mod == 1) "\x1b[F" else std.fmt.bufPrint(&buf, "\x1b[1;{d}F", .{mod}) catch "", // VK_END
                0x21 => if (mod == 1) "\x1b[5~" else std.fmt.bufPrint(&buf, "\x1b[5;{d}~", .{mod}) catch "", // VK_PRIOR (PageUp)
                0x22 => if (mod == 1) "\x1b[6~" else std.fmt.bufPrint(&buf, "\x1b[6;{d}~", .{mod}) catch "", // VK_NEXT (PageDown)
                0x2E => if (mod == 1) "\x1b[3~" else std.fmt.bufPrint(&buf, "\x1b[3;{d}~", .{mod}) catch "", // VK_DELETE
                0x60 => "0", // VK_NUMPAD0
                0x61 => "1", // VK_NUMPAD1
                0x62 => "2", // VK_NUMPAD2
                0x63 => "3", // VK_NUMPAD3
                0x64 => "4", // VK_NUMPAD4
                0x65 => "5", // VK_NUMPAD5
                0x66 => "6", // VK_NUMPAD6
                0x67 => "7", // VK_NUMPAD7
                0x68 => "8", // VK_NUMPAD8
                0x69 => "9", // VK_NUMPAD9
                0x6B => "+", // VK_ADD (Numpad +)
                0x6D => "-", // VK_SUBTRACT (Numpad -)
                0x70 => "\x1bOP", // VK_F1
                0x71 => "\x1bOQ", // VK_F2
                0x72 => if (shift) "\x1b[1;2R" else "\x1bOR", // VK_F3
                0x73 => "\x1bOS", // VK_F4
                0x74 => "\x1b[15~", // VK_F5
                else => "",
            };
            if (seq.len > 0) {
                try self.in_buf.appendSlice(seq);
                return seq.len;
            }
        }
        return 0;
    }

    pub fn readEvent(self: *Terminal, timeout_ms: i32) !Event {
        // Check resize before reading input
        if (self.checkResize()) {
            return .resize;
        }

        // Handle ongoing bracketed paste
        if (self.in_paste) {
            return try self.readBracketedPaste();
        }

        if (self.in_buf.items.len == 0) {
            _ = try self.readMoreBytes(timeout_ms);
            if (self.checkResize()) {
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
