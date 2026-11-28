const std = @import("std");
const builtin = @import("builtin");
const Term = @import("terminal.zig");

const is_windows = builtin.os.tag == .windows;

const w32 = if (is_windows) struct {
    const w = std.os.windows;
    const HANDLE = w.HANDLE;
    const HWND = HANDLE;
    const HDC = HANDLE;
    const HFONT = HANDLE;
    const HBITMAP = HANDLE;
    const HBRUSH = HANDLE;
    const HINSTANCE = HANDLE;
    const HICON = HANDLE;
    const HCURSOR = HANDLE;
    const HMENU = HANDLE;
    const DWORD = w.DWORD;
    const BOOL = w.BOOL;
    const WORD = w.WORD;
    const UINT = c_uint;
    const WPARAM = usize;
    const LPARAM = isize;
    const LRESULT = isize;
    const WCHAR = u16;
    const COLORREF = DWORD;

    const WS_OVERLAPPEDWINDOW: DWORD = 0x00CF0000;
    const WS_VISIBLE: DWORD = 0x10000000;
    const CW_USEDEFAULT: c_int = @bitCast(@as(c_uint, 0x80000000));

    const CS_HREDRAW: UINT = 0x0002;
    const CS_VREDRAW: UINT = 0x0001;
    const CS_OWNDC: UINT = 0x0020;

    const WM_DESTROY: UINT = 0x0002;
    const WM_SIZE: UINT = 0x0005;
    const WM_PAINT: UINT = 0x000F;
    const WM_CLOSE: UINT = 0x0010;
    const WM_QUIT: UINT = 0x0012;
    const WM_ERASEBKGND: UINT = 0x0014;
    const WM_KEYDOWN: UINT = 0x0100;
    const WM_KEYUP: UINT = 0x0101;
    const WM_CHAR: UINT = 0x0102;
    const WM_SYSKEYDOWN: UINT = 0x0104;
    const WM_SYSCHAR: UINT = 0x0106;
    const WM_MOUSEMOVE: UINT = 0x0200;
    const WM_LBUTTONDOWN: UINT = 0x0201;
    const WM_LBUTTONUP: UINT = 0x0202;
    const WM_RBUTTONDOWN: UINT = 0x0204;
    const WM_RBUTTONUP: UINT = 0x0205;
    const WM_MBUTTONDOWN: UINT = 0x0207;
    const WM_MBUTTONUP: UINT = 0x0208;
    const WM_MOUSEWHEEL: UINT = 0x020A;
    const WM_IME_CHAR: UINT = 0x0286;

    const PM_REMOVE: UINT = 0x0001;
    const MK_LBUTTON: usize = 0x0001;
    const SRCCOPY: DWORD = 0x00CC0020;
    const TRANSPARENT: c_int = 1;
    const OPAQUE: c_int = 2;
    const ETO_OPAQUE: UINT = 0x0002;
    const ETO_CLIPPED: UINT = 0x0004;
    const CLEARTYPE_QUALITY: u8 = 5;
    const FIXED_PITCH: u8 = 1;
    const FF_MODERN: u8 = 48;
    const DEFAULT_CHARSET: u8 = 1;
    const IDC_IBEAM: usize = 32513;
    const IDC_ARROW: usize = 32512;
    const SW_SHOW: c_int = 5;
    const SW_HIDE: c_int = 0;

    const VK_BACK: usize = 0x08;
    const VK_TAB: usize = 0x09;
    const VK_RETURN: usize = 0x0D;
    const VK_SHIFT: c_int = 0x10;
    const VK_CONTROL: c_int = 0x11;
    const VK_MENU: c_int = 0x12; // Alt
    const VK_ESCAPE: usize = 0x1B;
    const VK_PRIOR: usize = 0x21; // PageUp
    const VK_NEXT: usize = 0x22; // PageDown
    const VK_END: usize = 0x23;
    const VK_HOME: usize = 0x24;
    const VK_LEFT: usize = 0x25;
    const VK_UP: usize = 0x26;
    const VK_RIGHT: usize = 0x27;
    const VK_DOWN: usize = 0x28;
    const VK_DELETE: usize = 0x2E;
    const VK_NUMPAD0: usize = 0x60;
    const VK_NUMPAD9: usize = 0x69;
    const VK_ADD: usize = 0x6B;
    const VK_SUBTRACT: usize = 0x6D;
    const VK_F1: usize = 0x70;
    const VK_F2: usize = 0x71;
    const VK_F3: usize = 0x72;
    const VK_F4: usize = 0x73;
    const VK_F5: usize = 0x74;
    const VK_F6: usize = 0x75;
    const VK_F7: usize = 0x76;
    const VK_F8: usize = 0x77;
    const VK_F9: usize = 0x78;
    const VK_F10: usize = 0x79;
    const VK_F11: usize = 0x7A;
    const VK_F12: usize = 0x7B;
    const VK_OEM_PLUS: usize = 0xBB;
    const VK_OEM_MINUS: usize = 0xBD;

    const POINT = extern struct {
        x: i32,
        y: i32,
    };

    const RECT = extern struct {
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
    };

    const SIZE = extern struct {
        cx: i32,
        cy: i32,
    };

    const PAINTSTRUCT = extern struct {
        hdc: HDC,
        fErase: BOOL,
        rcPaint: RECT,
        fRestore: BOOL,
        fIncUpdate: BOOL,
        rgbReserved: [32]u8,
    };

    const MSG = extern struct {
        hwnd: ?HWND,
        message: UINT,
        wParam: WPARAM,
        lParam: LPARAM,
        time: DWORD,
        pt: POINT,
    };

    const WNDPROC = *const fn (hwnd: HWND, uMsg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(w.WINAPI) LRESULT;

    const WNDCLASSEXW = extern struct {
        cbSize: UINT = @sizeOf(WNDCLASSEXW),
        style: UINT = 0,
        lpfnWndProc: WNDPROC,
        cbClsExtra: c_int = 0,
        cbWndExtra: c_int = 0,
        hInstance: HINSTANCE,
        hIcon: ?HICON = null,
        hCursor: ?HCURSOR = null,
        hbrBackground: ?HBRUSH = null,
        lpszMenuName: ?[*:0]const WCHAR = null,
        lpszClassName: [*:0]const WCHAR,
        hIconSm: ?HICON = null,
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
        lfCharSet: u8 = 1,
        lfOutPrecision: u8 = 0,
        lfClipPrecision: u8 = 0,
        lfQuality: u8 = 5,
        lfPitchAndFamily: u8 = 0,
        lfFaceName: [32]WCHAR = [_]WCHAR{0} ** 32,
    };

    const TEXTMETRICW = extern struct {
        tmHeight: i32,
        tmAscent: i32,
        tmDescent: i32,
        tmInternalLeading: i32,
        tmExternalLeading: i32,
        tmAveCharWidth: i32,
        tmMaxCharWidth: i32,
        tmWeight: i32,
        tmOverhang: i32,
        tmDigitizedAspectX: i32,
        tmDigitizedAspectY: i32,
        tmFirstChar: WCHAR,
        tmLastChar: WCHAR,
        tmDefaultChar: WCHAR,
        tmBreakChar: WCHAR,
        tmItalic: u8,
        tmUnderlined: u8,
        tmStruckOut: u8,
        tmPitchAndFamily: u8,
        tmCharSet: u8,
    };

    extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const WCHAR) callconv(w.WINAPI) HINSTANCE;
    extern "kernel32" fn GetConsoleWindow() callconv(w.WINAPI) ?HWND;

    extern "user32" fn RegisterClassExW(lpwcx: *const WNDCLASSEXW) callconv(w.WINAPI) WORD;
    extern "user32" fn CreateWindowExW(
        dwExStyle: DWORD,
        lpClassName: [*:0]const WCHAR,
        lpWindowName: [*:0]const WCHAR,
        dwStyle: DWORD,
        X: c_int,
        Y: c_int,
        nWidth: c_int,
        nHeight: c_int,
        hWndParent: ?HWND,
        hMenu: ?HMENU,
        hInstance: HINSTANCE,
        lpParam: ?*anyopaque,
    ) callconv(w.WINAPI) ?HWND;
    extern "user32" fn DestroyWindow(hWnd: HWND) callconv(w.WINAPI) BOOL;
    extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: c_int) callconv(w.WINAPI) BOOL;
    extern "user32" fn UpdateWindow(hWnd: HWND) callconv(w.WINAPI) BOOL;
    extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(w.WINAPI) BOOL;
    extern "user32" fn SetFocus(hWnd: ?HWND) callconv(w.WINAPI) ?HWND;
    extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(w.WINAPI) LRESULT;
    extern "user32" fn PeekMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(w.WINAPI) BOOL;
    extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(w.WINAPI) BOOL;
    extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(w.WINAPI) LRESULT;
    extern "user32" fn MsgWaitForMultipleObjects(nCount: DWORD, pHandles: ?[*]const HANDLE, fWaitAll: BOOL, dwMilliseconds: DWORD, dwWakeMask: DWORD) callconv(w.WINAPI) DWORD;
    extern "user32" fn GetKeyState(nVirtKey: c_int) callconv(w.WINAPI) i16;
    extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(w.WINAPI) BOOL;
    extern "user32" fn InvalidateRect(hWnd: HWND, lpRect: ?*const RECT, bErase: BOOL) callconv(w.WINAPI) BOOL;
    extern "user32" fn BeginPaint(hWnd: HWND, lpPaint: *PAINTSTRUCT) callconv(w.WINAPI) HDC;
    extern "user32" fn EndPaint(hWnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(w.WINAPI) BOOL;
    extern "user32" fn GetDC(hWnd: ?HWND) callconv(w.WINAPI) ?HDC;
    extern "user32" fn ReleaseDC(hWnd: ?HWND, hDC: HDC) callconv(w.WINAPI) c_int;
    extern "user32" fn LoadCursorW(hInstance: ?HINSTANCE, lpCursorName: usize) callconv(w.WINAPI) ?HCURSOR;
    extern "user32" fn SetWindowTextW(hWnd: HWND, lpString: [*:0]const WCHAR) callconv(w.WINAPI) BOOL;
    extern "user32" fn SetCapture(hWnd: HWND) callconv(w.WINAPI) ?HWND;
    extern "user32" fn ReleaseCapture() callconv(w.WINAPI) BOOL;
    extern "user32" fn OpenClipboard(hWndNewOwner: ?HWND) callconv(w.WINAPI) BOOL;
    extern "user32" fn CloseClipboard() callconv(w.WINAPI) BOOL;
    extern "user32" fn EmptyClipboard() callconv(w.WINAPI) BOOL;
    extern "user32" fn SetClipboardData(uFormat: UINT, hMem: HANDLE) callconv(w.WINAPI) ?HANDLE;
    extern "kernel32" fn GlobalAlloc(uFlags: UINT, dwBytes: usize) callconv(w.WINAPI) ?HANDLE;
    extern "kernel32" fn GlobalLock(hMem: HANDLE) callconv(w.WINAPI) ?*anyopaque;
    extern "kernel32" fn GlobalUnlock(hMem: HANDLE) callconv(w.WINAPI) BOOL;

    extern "gdi32" fn CreateCompatibleDC(hdc: ?HDC) callconv(w.WINAPI) ?HDC;
    extern "gdi32" fn DeleteDC(hdc: HDC) callconv(w.WINAPI) BOOL;
    extern "gdi32" fn CreateCompatibleBitmap(hdc: HDC, cx: c_int, cy: c_int) callconv(w.WINAPI) ?HBITMAP;
    extern "gdi32" fn SelectObject(hdc: HDC, h: HANDLE) callconv(w.WINAPI) ?HANDLE;
    extern "gdi32" fn DeleteObject(ho: HANDLE) callconv(w.WINAPI) BOOL;
    extern "gdi32" fn CreateFontIndirectW(lplf: *const LOGFONTW) callconv(w.WINAPI) ?HFONT;
    extern "gdi32" fn CreateFontIndirectA(lplf: *const anyopaque) callconv(w.WINAPI) ?HFONT;
    extern "gdi32" fn GetTextMetricsW(hdc: HDC, lptm: *TEXTMETRICW) callconv(w.WINAPI) BOOL;
    extern "gdi32" fn GetTextExtentPoint32W(hdc: HDC, lpString: [*]const WCHAR, c: c_int, psizl: *SIZE) callconv(w.WINAPI) BOOL;
    extern "gdi32" fn SetTextColor(hdc: HDC, color: COLORREF) callconv(w.WINAPI) COLORREF;
    extern "gdi32" fn SetBkColor(hdc: HDC, color: COLORREF) callconv(w.WINAPI) COLORREF;
    extern "gdi32" fn SetBkMode(hdc: HDC, mode: c_int) callconv(w.WINAPI) c_int;
    extern "gdi32" fn ExtTextOutW(
        hdc: HDC,
        x: c_int,
        y: c_int,
        options: UINT,
        lprect: ?*const RECT,
        lpString: ?[*]const WCHAR,
        c: UINT,
        lpDx: ?[*]const c_int,
    ) callconv(w.WINAPI) BOOL;
    extern "gdi32" fn BitBlt(
        hdc: HDC,
        x: c_int,
        y: c_int,
        cx: c_int,
        cy: c_int,
        hdcSrc: HDC,
        x1: c_int,
        y1: c_int,
        rop: DWORD,
    ) callconv(w.WINAPI) BOOL;

    fn rgb(r: u8, g: u8, b: u8) COLORREF {
        return @as(DWORD, r) | (@as(DWORD, g) << 8) | (@as(DWORD, b) << 16);
    }
} else struct {};

pub const Cell = struct {
    cp: u21 = ' ',
    fg_r: u8 = 205,
    fg_g: u8 = 214,
    fg_b: u8 = 244,
    bg_r: u8 = 30,
    bg_g: u8 = 30,
    bg_b: u8 = 46,
    bold: bool = false,
    wide_lead: bool = false,
    wide_trail: bool = false,
};

var g_gui: if (is_windows) ?*Win32Gui else void = if (is_windows) null else {};

pub const Win32Gui = if (is_windows) struct {
    allocator: std.mem.Allocator,
    term: *Term.Terminal,
    hwnd: w32.HWND,
    mem_dc: ?w32.HDC = null,
    mem_bmp: ?w32.HBITMAP = null,
    old_bmp: ?w32.HANDLE = null,
    bmp_w: i32 = 0,
    bmp_h: i32 = 0,

    hfont_normal: ?w32.HFONT = null,
    hfont_bold: ?w32.HFONT = null,
    cell_w: i32 = 9,
    cell_h: i32 = 18,
    cols: usize = 120,
    rows: usize = 36,
    resized: bool = false,
    closed: bool = false,

    cells: std.ArrayList(Cell),
    cur_row: usize = 0,
    cur_col: usize = 0,
    cursor_visible: bool = true,
    cur_fg: [3]u8 = .{ 205, 214, 244 },
    cur_bg: [3]u8 = .{ 30, 30, 46 },
    cur_bold: bool = false,

    // ANSI escape parser state
    esc_state: enum { normal, esc, csi, osc } = .normal,
    csi_buf: [64]u8 = undefined,
    csi_len: usize = 0,
    utf8_buf: [4]u8 = undefined,
    utf8_len: usize = 0,
    utf8_need: usize = 0,

    // Surrogate pair state for WM_CHAR
    high_surrogate: ?u16 = null,
    suppress_next_char: bool = false,

    pub fn init(allocator: std.mem.Allocator, term: *Term.Terminal) !*Win32Gui {
        const self = try allocator.create(Win32Gui);
        self.* = .{
            .allocator = allocator,
            .term = term,
            .hwnd = undefined,
            .cells = std.ArrayList(Cell).init(allocator),
        };
        g_gui = self;

        const hinst = w32.GetModuleHandleW(null);
        const class_name = [_:0]u16{ 'Z', 'e', 'd', 'i', 't', 'G', 'u', 'i', 'W', 'n', 'd' };
        const wc = w32.WNDCLASSEXW{
            .lpfnWndProc = wndProc,
            .hInstance = hinst,
            .hCursor = w32.LoadCursorW(null, w32.IDC_IBEAM),
            .lpszClassName = &class_name,
            .style = w32.CS_HREDRAW | w32.CS_VREDRAW | w32.CS_OWNDC,
        };
        _ = w32.RegisterClassExW(&wc);

        const title = [_:0]u16{ 'z', 'e', 'd', 'i', 't' };
        const hwnd = w32.CreateWindowExW(
            0,
            &class_name,
            &title,
            w32.WS_OVERLAPPEDWINDOW | w32.WS_VISIBLE,
            w32.CW_USEDEFAULT,
            w32.CW_USEDEFAULT,
            1120,
            740,
            null,
            null,
            hinst,
            null,
        ) orelse {
            allocator.destroy(self);
            g_gui = null;
            return error.WindowCreationFailed;
        };
        self.hwnd = hwnd;

        try self.resizeGrid(120, 36);
        self.setFont(term.active_font_name, term.font_height);

        // Update grid dimensions based on actual client rect and font cell size
        var rc: w32.RECT = undefined;
        if (w32.GetClientRect(hwnd, &rc) != 0) {
            const cw = @max(@divTrunc(rc.right - rc.left, @max(self.cell_w, 1)), 20);
            const ch = @max(@divTrunc(rc.bottom - rc.top, @max(self.cell_h, 1)), 6);
            try self.resizeGrid(@intCast(cw), @intCast(ch));
        }

        _ = w32.ShowWindow(hwnd, w32.SW_SHOW);
        _ = w32.UpdateWindow(hwnd);
        _ = w32.SetForegroundWindow(hwnd);
        _ = w32.SetFocus(hwnd);

        return self;
    }

    pub fn deinit(self: *Win32Gui) void {
        g_gui = null;
        if (self.hfont_normal) |f| _ = w32.DeleteObject(f);
        if (self.hfont_bold) |f| _ = w32.DeleteObject(f);
        if (self.mem_dc) |dc| {
            if (self.old_bmp) |ob| _ = w32.SelectObject(dc, ob);
            if (self.mem_bmp) |bmp| _ = w32.DeleteObject(bmp);
            _ = w32.DeleteDC(dc);
        }
        _ = w32.DestroyWindow(self.hwnd);
        self.cells.deinit();
        self.allocator.destroy(self);
    }

    pub fn resizeGrid(self: *Win32Gui, new_cols: usize, new_rows: usize) !void {
        const c = @max(new_cols, 10);
        const r = @max(new_rows, 4);
        const total = c * r;
        try self.cells.resize(total);
        for (self.cells.items) |*cell| {
            cell.* = .{};
        }
        self.cols = c;
        self.rows = r;
        self.cur_row = @min(self.cur_row, r - 1);
        self.cur_col = @min(self.cur_col, c - 1);
    }

    pub fn setFont(self: *Win32Gui, face_utf8: []const u8, height_pt: i16) void {
        var lf = w32.LOGFONTW{
            .lfHeight = -@as(i32, @max(height_pt, 10)),
            .lfWidth = 0,
            .lfWeight = 400,
            .lfCharSet = w32.DEFAULT_CHARSET,
            .lfQuality = w32.CLEARTYPE_QUALITY,
            .lfPitchAndFamily = w32.FIXED_PITCH | w32.FF_MODERN,
        };
        const wlen = std.unicode.utf8ToUtf16Le(&lf.lfFaceName, face_utf8) catch 0;
        if (wlen < lf.lfFaceName.len) lf.lfFaceName[wlen] = 0;

        const new_normal = w32.CreateFontIndirectW(&lf);
        lf.lfWeight = 700;
        const new_bold = w32.CreateFontIndirectW(&lf);

        if (new_normal) |nf| {
            if (self.hfont_normal) |old| _ = w32.DeleteObject(old);
            self.hfont_normal = nf;
        }
        if (new_bold) |bf| {
            if (self.hfont_bold) |old| _ = w32.DeleteObject(old);
            self.hfont_bold = bf;
        }

        // Measure exact halfwidth cell dimensions ('M' / 'A')
        if (w32.GetDC(self.hwnd)) |hdc| {
            defer _ = w32.ReleaseDC(self.hwnd, hdc);
            const prev = if (self.hfont_normal) |nf| w32.SelectObject(hdc, nf) else null;
            defer if (prev) |p| {
                _ = w32.SelectObject(hdc, p);
            };

            var tm: w32.TEXTMETRICW = undefined;
            var sz_M = w32.SIZE{ .cx = 9, .cy = 18 };
            const ch_M = [1]u16{'M'};
            _ = w32.GetTextExtentPoint32W(hdc, &ch_M, 1, &sz_M);
            if (w32.GetTextMetricsW(hdc, &tm) != 0) {
                self.cell_w = @max(sz_M.cx, @max(tm.tmAveCharWidth, 5));
                self.cell_h = @max(tm.tmHeight + tm.tmExternalLeading, 10);
            } else {
                self.cell_w = @max(sz_M.cx, 6);
                self.cell_h = @max(sz_M.cy, 12);
            }
        }

        // Update window title to show current font & size
        var title_buf: [192]u8 = undefined;
        const title_utf8 = std.fmt.bufPrint(&title_buf, "zedit — {s} ({d}px)", .{ face_utf8, height_pt }) catch "zedit";
        var title_w: [192:0]u16 = [_:0]u16{0} ** 192;
        if (std.unicode.utf8ToUtf16Le(&title_w, title_utf8)) |tlen| {
            title_w[tlen] = 0;
            _ = w32.SetWindowTextW(self.hwnd, &title_w);
        } else |_| {}

        // Recompute grid cols/rows for new cell metrics!
        var rc: w32.RECT = undefined;
        if (w32.GetClientRect(self.hwnd, &rc) != 0) {
            const new_c: usize = @intCast(@max(@divTrunc(rc.right - rc.left, @max(self.cell_w, 1)), 10));
            const new_r: usize = @intCast(@max(@divTrunc(rc.bottom - rc.top, @max(self.cell_h, 1)), 4));
            if (new_c != self.cols or new_r != self.rows) {
                self.resizeGrid(new_c, new_r) catch {};
                self.resized = true;
            }
        }
        _ = w32.InvalidateRect(self.hwnd, null, 0);
    }

    pub fn pumpMessages(self: *Win32Gui, term: *Term.Terminal, timeout_ms: i32) void {
        self.term = term;
        var msg: w32.MSG = undefined;
        if (w32.PeekMessageW(&msg, null, 0, 0, w32.PM_REMOVE) == 0 and timeout_ms > 0 and self.term.in_buf.items.len == 0 and !self.resized and !self.closed) {
            _ = w32.MsgWaitForMultipleObjects(0, null, 0, @intCast(timeout_ms), 0x04FF); // QS_ALLINPUT
        }
        while (w32.PeekMessageW(&msg, null, 0, 0, w32.PM_REMOVE) != 0) {
            if (msg.message == w32.WM_QUIT) {
                self.closed = true;
                self.term.in_buf.append(0x11) catch {}; // Ctrl+Q
                return;
            }
            _ = w32.TranslateMessage(&msg);
            _ = w32.DispatchMessageW(&msg);
        }
    }

    pub fn writeAnsi(self: *Win32Gui, term: *Term.Terminal, bytes: []const u8) void {
        self.term = term;
        for (bytes) |b| {
            self.feedByte(b);
        }
        if (w32.GetDC(self.hwnd)) |hdc| {
            defer _ = w32.ReleaseDC(self.hwnd, hdc);
            self.paintToDC(hdc);
        }
    }

    fn feedByte(self: *Win32Gui, b: u8) void {
        switch (self.esc_state) {
            .normal => {
                if (b == 0x1b) {
                    self.esc_state = .esc;
                    self.utf8_len = 0;
                    self.utf8_need = 0;
                    return;
                }
                if (b == '\r') {
                    self.cur_col = 0;
                    return;
                }
                if (b == '\n') {
                    if (self.cur_row + 1 < self.rows) self.cur_row += 1;
                    return;
                }
                if (b < 0x80) {
                    self.putCodepoint(b);
                    return;
                }
                if ((b & 0xE0) == 0xC0) {
                    self.utf8_buf[0] = b;
                    self.utf8_len = 1;
                    self.utf8_need = 2;
                } else if ((b & 0xF0) == 0xE0) {
                    self.utf8_buf[0] = b;
                    self.utf8_len = 1;
                    self.utf8_need = 3;
                } else if ((b & 0xF8) == 0xF0) {
                    self.utf8_buf[0] = b;
                    self.utf8_len = 1;
                    self.utf8_need = 4;
                } else if ((b & 0xC0) == 0x80 and self.utf8_len > 0 and self.utf8_len < self.utf8_need) {
                    self.utf8_buf[self.utf8_len] = b;
                    self.utf8_len += 1;
                    if (self.utf8_len == self.utf8_need) {
                        const cp = std.unicode.utf8Decode(self.utf8_buf[0..self.utf8_need]) catch '?';
                        self.utf8_len = 0;
                        self.utf8_need = 0;
                        self.putCodepoint(cp);
                    }
                } else {
                    self.utf8_len = 0;
                    self.utf8_need = 0;
                }
            },
            .esc => {
                if (b == '[') {
                    self.esc_state = .csi;
                    self.csi_len = 0;
                } else if (b == ']') {
                    self.esc_state = .osc;
                } else {
                    self.esc_state = .normal;
                }
            },
            .osc => {
                if (b == 0x07) {
                    self.esc_state = .normal;
                }
            },
            .csi => {
                if (b >= 0x40 and b <= 0x7E) {
                    self.handleCsi(self.csi_buf[0..self.csi_len], b);
                    self.esc_state = .normal;
                } else if (self.csi_len < self.csi_buf.len) {
                    self.csi_buf[self.csi_len] = b;
                    self.csi_len += 1;
                }
            },
        }
    }

    fn handleCsi(self: *Win32Gui, params: []const u8, final: u8) void {
        if (params.len > 0 and params[0] == '?') {
            if (std.mem.eql(u8, params[1..], "25")) {
                self.cursor_visible = (final == 'h');
            }
            return;
        }

        var nums: [16]usize = [_]usize{0} ** 16;
        var count: usize = 0;
        if (params.len > 0) {
            var it = std.mem.splitScalar(u8, params, ';');
            while (it.next()) |part| {
                if (count >= nums.len) break;
                nums[count] = std.fmt.parseInt(usize, part, 10) catch 0;
                count += 1;
            }
        }

        switch (final) {
            'H', 'f' => {
                const r = if (count >= 1 and nums[0] > 0) nums[0] - 1 else 0;
                const c = if (count >= 2 and nums[1] > 0) nums[1] - 1 else 0;
                self.cur_row = @min(r, self.rows - 1);
                self.cur_col = @min(c, self.cols - 1);
            },
            'G' => {
                const c = if (count >= 1 and nums[0] > 0) nums[0] - 1 else 0;
                self.cur_col = @min(c, self.cols - 1);
            },
            'J' => {
                const mode = if (count >= 1) nums[0] else 0;
                if (mode == 2) {
                    for (self.cells.items) |*cell| {
                        cell.* = .{
                            .cp = ' ',
                            .fg_r = self.cur_fg[0],
                            .fg_g = self.cur_fg[1],
                            .fg_b = self.cur_fg[2],
                            .bg_r = self.cur_bg[0],
                            .bg_g = self.cur_bg[1],
                            .bg_b = self.cur_bg[2],
                        };
                    }
                }
            },
            'K' => {
                var c = self.cur_col;
                while (c < self.cols) : (c += 1) {
                    self.cells.items[self.cur_row * self.cols + c] = .{
                        .cp = ' ',
                        .fg_r = self.cur_fg[0],
                        .fg_g = self.cur_fg[1],
                        .fg_b = self.cur_fg[2],
                        .bg_r = self.cur_bg[0],
                        .bg_g = self.cur_bg[1],
                        .bg_b = self.cur_bg[2],
                    };
                }
            },
            'm' => {
                if (count == 0) {
                    self.resetStyle();
                    return;
                }
                var i: usize = 0;
                while (i < count) : (i += 1) {
                    const code = nums[i];
                    if (code == 0) {
                        self.resetStyle();
                    } else if (code == 1) {
                        self.cur_bold = true;
                    } else if (code == 22) {
                        self.cur_bold = false;
                    } else if (code == 38 and i + 4 < count and nums[i + 1] == 2) {
                        self.cur_fg = .{
                            @intCast(@min(nums[i + 2], 255)),
                            @intCast(@min(nums[i + 3], 255)),
                            @intCast(@min(nums[i + 4], 255)),
                        };
                        i += 4;
                    } else if (code == 48 and i + 4 < count and nums[i + 1] == 2) {
                        self.cur_bg = .{
                            @intCast(@min(nums[i + 2], 255)),
                            @intCast(@min(nums[i + 3], 255)),
                            @intCast(@min(nums[i + 4], 255)),
                        };
                        i += 4;
                    }
                }
            },
            else => {},
        }
    }

    fn resetStyle(self: *Win32Gui) void {
        self.cur_fg = .{ 205, 214, 244 };
        self.cur_bg = .{ 30, 30, 46 };
        self.cur_bold = false;
    }

    fn putCodepoint(self: *Win32Gui, cp: u21) void {
        if (self.cur_row >= self.rows or self.cur_col >= self.cols) return;
        const cw = @import("editor.zig").codepointWidth(cp);
        if (cw == 0) return;

        const idx = self.cur_row * self.cols + self.cur_col;
        if (cw == 2 and self.cur_col + 1 < self.cols) {
            self.cells.items[idx] = .{
                .cp = cp,
                .fg_r = self.cur_fg[0],
                .fg_g = self.cur_fg[1],
                .fg_b = self.cur_fg[2],
                .bg_r = self.cur_bg[0],
                .bg_g = self.cur_bg[1],
                .bg_b = self.cur_bg[2],
                .bold = self.cur_bold,
                .wide_lead = true,
                .wide_trail = false,
            };
            self.cells.items[idx + 1] = .{
                .cp = ' ',
                .fg_r = self.cur_fg[0],
                .fg_g = self.cur_fg[1],
                .fg_b = self.cur_fg[2],
                .bg_r = self.cur_bg[0],
                .bg_g = self.cur_bg[1],
                .bg_b = self.cur_bg[2],
                .bold = self.cur_bold,
                .wide_lead = false,
                .wide_trail = true,
            };
            self.cur_col = @min(self.cur_col + 2, self.cols);
        } else {
            self.cells.items[idx] = .{
                .cp = cp,
                .fg_r = self.cur_fg[0],
                .fg_g = self.cur_fg[1],
                .fg_b = self.cur_fg[2],
                .bg_r = self.cur_bg[0],
                .bg_g = self.cur_bg[1],
                .bg_b = self.cur_bg[2],
                .bold = self.cur_bold,
                .wide_lead = false,
                .wide_trail = false,
            };
            self.cur_col = @min(self.cur_col + 1, self.cols);
        }
    }

    pub fn paintToDC(self: *Win32Gui, target_dc: w32.HDC) void {
        var rc: w32.RECT = undefined;
        if (w32.GetClientRect(self.hwnd, &rc) == 0) return;
        const win_w = @max(rc.right - rc.left, 1);
        const win_h = @max(rc.bottom - rc.top, 1);

        // Recreate offscreen double-buffer bitmap if window size changed
        if (self.mem_dc == null or win_w != self.bmp_w or win_h != self.bmp_h) {
            if (self.mem_dc) |dc| {
                if (self.old_bmp) |ob| _ = w32.SelectObject(dc, ob);
                if (self.mem_bmp) |bmp| _ = w32.DeleteObject(bmp);
                _ = w32.DeleteDC(dc);
            }
            self.mem_dc = w32.CreateCompatibleDC(target_dc);
            if (self.mem_dc) |dc| {
                self.mem_bmp = w32.CreateCompatibleBitmap(target_dc, win_w, win_h);
                if (self.mem_bmp) |bmp| {
                    self.old_bmp = w32.SelectObject(dc, bmp);
                }
            }
            self.bmp_w = win_w;
            self.bmp_h = win_h;
        }

        const dc = self.mem_dc orelse target_dc;
        _ = w32.SetBkMode(dc, w32.OPAQUE);

        // Clear any leftover margin at right/bottom edge
        const full_rect = w32.RECT{ .left = 0, .top = 0, .right = win_w, .bottom = win_h };
        _ = w32.SetBkColor(dc, w32.rgb(24, 24, 37));
        _ = w32.ExtTextOutW(dc, 0, 0, w32.ETO_OPAQUE, &full_rect, null, 0, null);

        var cur_bold_sel: ?bool = null;
        if (self.hfont_normal) |nf| {
            _ = w32.SelectObject(dc, nf);
            cur_bold_sel = false;
        }

        // Draw every cell pinned strictly to its 1:2 pixel grid coordinate!
        // Halfwidth cell = cell_w px wide; Fullwidth cell (wide_lead) = cell_w * 2 px wide.
        var r: usize = 0;
        while (r < self.rows) : (r += 1) {
            const py: i32 = @as(i32, @intCast(r)) * self.cell_h;
            var c: usize = 0;
            while (c < self.cols) : (c += 1) {
                const cell = self.cells.items[r * self.cols + c];
                if (cell.wide_trail) continue;

                const px: i32 = @as(i32, @intCast(c)) * self.cell_w;
                const box_w: i32 = if (cell.wide_lead and c + 1 < self.cols) self.cell_w * 2 else self.cell_w;
                const cell_rect = w32.RECT{
                    .left = px,
                    .top = py,
                    .right = px + box_w,
                    .bottom = py + self.cell_h,
                };

                if (cur_bold_sel == null or cur_bold_sel.? != cell.bold) {
                    const f = if (cell.bold) (self.hfont_bold orelse self.hfont_normal) else self.hfont_normal;
                    if (f) |hf| _ = w32.SelectObject(dc, hf);
                    cur_bold_sel = cell.bold;
                }

                _ = w32.SetTextColor(dc, w32.rgb(cell.fg_r, cell.fg_g, cell.fg_b));
                _ = w32.SetBkColor(dc, w32.rgb(cell.bg_r, cell.bg_g, cell.bg_b));

                if (cell.cp == ' ' or cell.cp == 0) {
                    _ = w32.ExtTextOutW(dc, px, py, w32.ETO_OPAQUE, &cell_rect, null, 0, null);
                } else {
                    var u16_buf: [2]u16 = undefined;
                    var u16_len: w32.UINT = 1;
                    if (cell.cp <= 0xFFFF) {
                        u16_buf[0] = @intCast(cell.cp);
                    } else {
                        const v = cell.cp - 0x10000;
                        u16_buf[0] = @intCast(0xD800 + (v >> 10));
                        u16_buf[1] = @intCast(0xDC00 + (v & 0x3FF));
                        u16_len = 2;
                    }
                    _ = w32.ExtTextOutW(
                        dc,
                        px,
                        py,
                        w32.ETO_OPAQUE | w32.ETO_CLIPPED,
                        &cell_rect,
                        &u16_buf,
                        u16_len,
                        null,
                    );
                }
            }
        }

        // Draw cursor bar / inverted block if visible
        if (self.cursor_visible and self.cur_row < self.rows and self.cur_col < self.cols) {
            const cx: i32 = @as(i32, @intCast(self.cur_col)) * self.cell_w;
            const cy: i32 = @as(i32, @intCast(self.cur_row)) * self.cell_h;
            const cur_rect = w32.RECT{
                .left = cx,
                .top = cy,
                .right = cx + @max(@divTrunc(self.cell_w, 4), 2),
                .bottom = cy + self.cell_h,
            };
            _ = w32.SetBkColor(dc, w32.rgb(245, 224, 220));
            _ = w32.ExtTextOutW(dc, cx, cy, w32.ETO_OPAQUE, &cur_rect, null, 0, null);
        }

        if (self.mem_dc) |mdc| {
            _ = w32.BitBlt(target_dc, 0, 0, win_w, win_h, mdc, 0, 0, w32.SRCCOPY);
        }
    }

    pub fn setClipboard(self: *Win32Gui, text: []const u8) void {
        const w_slice = std.unicode.utf8ToUtf16LeAllocZ(self.allocator, text) catch return;
        defer self.allocator.free(w_slice);
        const byte_size = (w_slice.len + 1) * 2;

        if (w32.OpenClipboard(self.hwnd) == 0) return;
        defer _ = w32.CloseClipboard();
        _ = w32.EmptyClipboard();

        const GMEM_MOVEABLE: w32.UINT = 0x0002;
        const CF_UNICODETEXT: w32.UINT = 13;
        if (w32.GlobalAlloc(GMEM_MOVEABLE, byte_size)) |hmem| {
            if (w32.GlobalLock(hmem)) |ptr| {
                const dst: [*]u16 = @ptrCast(@alignCast(ptr));
                @memcpy(dst[0..w_slice.len], w_slice);
                dst[w_slice.len] = 0;
                _ = w32.GlobalUnlock(hmem);
                _ = w32.SetClipboardData(CF_UNICODETEXT, hmem);
            }
        }
    }

    fn isKeyDown(vk: c_int) bool {
        return (w32.GetKeyState(vk) & -0x8000) != 0;
    }

    fn handleKeyDown(self: *Win32Gui, vk: usize) bool {
        const shift = isKeyDown(w32.VK_SHIFT);
        const ctrl = isKeyDown(w32.VK_CONTROL);
        const alt = isKeyDown(w32.VK_MENU);
        const mod: u8 = 1 + (if (shift) @as(u8, 1) else 0) + (if (alt) @as(u8, 2) else 0) + (if (ctrl) @as(u8, 4) else 0);

        var buf: [16]u8 = undefined;
        const seq: []const u8 = switch (vk) {
            w32.VK_BACK => if (ctrl) "\x1b[127;5u" else if (alt) "\x1b\x7f" else "\x7f",
            w32.VK_TAB => if (ctrl and shift) "\x1b[27;6;9~" else if (ctrl) "\x1b[27;5;9~" else if (shift) "\x1b[Z" else "\t",
            w32.VK_RETURN => if (alt) "\x1b\r" else "\r",
            w32.VK_ESCAPE => "\x1b",
            w32.VK_UP => if (mod == 1) "\x1b[A" else std.fmt.bufPrint(&buf, "\x1b[1;{d}A", .{mod}) catch "",
            w32.VK_DOWN => if (mod == 1) "\x1b[B" else std.fmt.bufPrint(&buf, "\x1b[1;{d}B", .{mod}) catch "",
            w32.VK_RIGHT => if (mod == 1) "\x1b[C" else std.fmt.bufPrint(&buf, "\x1b[1;{d}C", .{mod}) catch "",
            w32.VK_LEFT => if (mod == 1) "\x1b[D" else std.fmt.bufPrint(&buf, "\x1b[1;{d}D", .{mod}) catch "",
            w32.VK_HOME => if (mod == 1) "\x1b[H" else std.fmt.bufPrint(&buf, "\x1b[1;{d}H", .{mod}) catch "",
            w32.VK_END => if (mod == 1) "\x1b[F" else std.fmt.bufPrint(&buf, "\x1b[1;{d}F", .{mod}) catch "",
            w32.VK_PRIOR => if (mod == 1) "\x1b[5~" else std.fmt.bufPrint(&buf, "\x1b[5;{d}~", .{mod}) catch "",
            w32.VK_NEXT => if (mod == 1) "\x1b[6~" else std.fmt.bufPrint(&buf, "\x1b[6;{d}~", .{mod}) catch "",
            w32.VK_DELETE => if (mod == 1) "\x1b[3~" else std.fmt.bufPrint(&buf, "\x1b[3;{d}~", .{mod}) catch "",
            w32.VK_F1 => "\x1bOP",
            w32.VK_F2 => "\x1bOQ",
            w32.VK_F3 => if (shift) "\x1b[1;2R" else "\x1bOR",
            w32.VK_F4 => "\x1bOS",
            w32.VK_F5 => "\x1b[15~",
            w32.VK_F6 => "\x1b[17~",
            w32.VK_F7 => "\x1b[18~",
            w32.VK_F8 => "\x1b[19~",
            w32.VK_F9 => "\x1b[20~",
            w32.VK_F10 => "\x1b[21~",
            w32.VK_F11 => "\x1b[23~",
            w32.VK_F12 => "\x1b[24~",
            else => "",
        };

        if (seq.len > 0) {
            self.term.in_buf.appendSlice(seq) catch {};
            self.suppress_next_char = true;
            return true;
        }

        // Ctrl+Shift+Z or Ctrl+letter
        if (ctrl and !alt and vk >= 'A' and vk <= 'Z') {
            if (shift and vk == 'Z') {
                self.term.in_buf.appendSlice("\x1b[90;6u") catch {};
            } else {
                const ctrl_byte: u8 = @intCast(vk - 'A' + 1);
                self.term.in_buf.append(ctrl_byte) catch {};
            }
            self.suppress_next_char = true;
            return true;
        }

        // Alt+letter / Alt+number / Alt+symbol
        if (alt and !ctrl) {
            if ((vk >= 'A' and vk <= 'Z') or (vk >= '0' and vk <= '9')) {
                const ch: u8 = if (vk >= 'A' and vk <= 'Z' and !shift)
                    @intCast(vk - 'A' + 'a')
                else
                    @intCast(vk);
                self.term.in_buf.append(0x1b) catch {};
                self.term.in_buf.append(ch) catch {};
                self.suppress_next_char = true;
                return true;
            }
            if (vk == w32.VK_OEM_PLUS or vk == w32.VK_ADD) {
                self.term.in_buf.appendSlice("\x1b+") catch {};
                self.suppress_next_char = true;
                return true;
            }
            if (vk == w32.VK_OEM_MINUS or vk == w32.VK_SUBTRACT) {
                self.term.in_buf.appendSlice("\x1b-") catch {};
                self.suppress_next_char = true;
                return true;
            }
        }

        self.suppress_next_char = false;
        return false;
    }

    fn handleChar(self: *Win32Gui, unit: u16) void {
        if (self.suppress_next_char) {
            self.suppress_next_char = false;
            return;
        }
        // Ignore control chars already handled in WM_KEYDOWN
        if (unit < 0x20) return;

        var cp: u21 = unit;
        if (unit >= 0xD800 and unit <= 0xDBFF) {
            self.high_surrogate = unit;
            return;
        } else if (unit >= 0xDC00 and unit <= 0xDFFF) {
            if (self.high_surrogate) |hi| {
                cp = 0x10000 + ((@as(u21, hi - 0xD800) << 10) | @as(u21, unit - 0xDC00));
                self.high_surrogate = null;
            } else {
                return;
            }
        } else {
            self.high_surrogate = null;
        }

        var out: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &out) catch return;
        self.term.in_buf.appendSlice(out[0..len]) catch {};
    }

    fn emitMouseSgr(self: *Win32Gui, btn: u8, lparam: w32.LPARAM, release: bool) void {
        const px: i16 = @bitCast(@as(u16, @truncate(@as(usize, @bitCast(lparam)))));
        const py: i16 = @bitCast(@as(u16, @truncate(@as(usize, @bitCast(lparam)) >> 16)));
        const col: usize = @intCast(@max(@divTrunc(@as(i32, px), @max(self.cell_w, 1)), 0) + 1);
        const row: usize = @intCast(@max(@divTrunc(@as(i32, py), @max(self.cell_h, 1)), 0) + 1);
        var sgr: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&sgr, "\x1b[<{d};{d};{d}{c}", .{
            btn,
            col,
            row,
            if (release) @as(u8, 'm') else 'M',
        }) catch return;
        self.term.in_buf.appendSlice(s) catch {};
    }

    fn wndProc(hwnd: w32.HWND, msg: w32.UINT, wparam: w32.WPARAM, lparam: w32.LPARAM) callconv(std.os.windows.WINAPI) w32.LRESULT {
        const self = g_gui orelse return w32.DefWindowProcW(hwnd, msg, wparam, lparam);
        switch (msg) {
            w32.WM_ERASEBKGND => return 1,
            w32.WM_PAINT => {
                var ps: w32.PAINTSTRUCT = undefined;
                const hdc = w32.BeginPaint(hwnd, &ps);
                self.paintToDC(hdc);
                _ = w32.EndPaint(hwnd, &ps);
                return 0;
            },
            w32.WM_SIZE => {
                const pix_w: i32 = @intCast(lparam & 0xFFFF);
                const pix_h: i32 = @intCast((lparam >> 16) & 0xFFFF);
                if (pix_w > 0 and pix_h > 0) {
                    const new_c: usize = @intCast(@max(@divTrunc(pix_w, @max(self.cell_w, 1)), 10));
                    const new_r: usize = @intCast(@max(@divTrunc(pix_h, @max(self.cell_h, 1)), 4));
                    if (new_c != self.cols or new_r != self.rows) {
                        self.resizeGrid(new_c, new_r) catch {};
                        self.resized = true;
                    }
                }
                return 0;
            },
            w32.WM_KEYDOWN, w32.WM_SYSKEYDOWN => {
                if (self.handleKeyDown(wparam)) {
                    return 0;
                }
                return w32.DefWindowProcW(hwnd, msg, wparam, lparam);
            },
            w32.WM_CHAR, w32.WM_SYSCHAR => {
                self.handleChar(@truncate(wparam));
                return 0;
            },
            w32.WM_LBUTTONDOWN => {
                _ = w32.SetCapture(hwnd);
                self.emitMouseSgr(0, lparam, false);
                return 0;
            },
            w32.WM_LBUTTONUP => {
                _ = w32.ReleaseCapture();
                self.emitMouseSgr(0, lparam, true);
                return 0;
            },
            w32.WM_MOUSEMOVE => {
                if ((wparam & w32.MK_LBUTTON) != 0) {
                    self.emitMouseSgr(32, lparam, false);
                }
                return 0;
            },
            w32.WM_MOUSEWHEEL => {
                const delta: i16 = @bitCast(@as(u16, @truncate(wparam >> 16)));
                const btn: u8 = if (delta > 0) 64 else 65;
                var sgr: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&sgr, "\x1b[<{d};{d};{d}M", .{ btn, self.cols / 2, self.rows / 2 }) catch "";
                self.term.in_buf.appendSlice(s) catch {};
                return 0;
            },
            w32.WM_CLOSE => {
                self.closed = true;
                self.term.in_buf.append(0x11) catch {}; // Send Ctrl+Q to editor
                return 0;
            },
            else => return w32.DefWindowProcW(hwnd, msg, wparam, lparam),
        }
    }
} else struct {};
