const std = @import("std");
const table = @import("cp932_table.zig");

pub const Encoding = enum(u8) {
    utf8,
    utf8_bom,
    shift_jis,
    euc_jp,
    iso_2022_jp,
    utf16_le,
    utf16_be,

    pub const all = [_]Encoding{
        .utf8,
        .utf8_bom,
        .shift_jis,
        .euc_jp,
        .iso_2022_jp,
        .utf16_le,
        .utf16_be,
    };

    pub fn name(self: Encoding) []const u8 {
        return switch (self) {
            .utf8 => "UTF-8",
            .utf8_bom => "UTF-8 BOM",
            .shift_jis => "Shift_JIS",
            .euc_jp => "EUC-JP",
            .iso_2022_jp => "ISO-2022-JP",
            .utf16_le => "UTF-16LE",
            .utf16_be => "UTF-16BE",
        };
    }

    pub fn parse(input: []const u8) ?Encoding {
        const s = std.mem.trim(u8, input, " \t\r\n");
        if (s.len == 0) return null;

        // Allow 1-based numeric index from picker ("1".."7")
        if (s.len == 1 and s[0] >= '1' and s[0] <= '7') {
            return all[s[0] - '1'];
        }

        if (eqlLoose(s, "utf8") or eqlLoose(s, "utf-8")) return .utf8;
        if (eqlLoose(s, "utf8bom") or eqlLoose(s, "utf-8bom") or eqlLoose(s, "utf-8-bom") or eqlLoose(s, "utf-8 bom")) return .utf8_bom;
        if (eqlLoose(s, "sjis") or eqlLoose(s, "shift_jis") or eqlLoose(s, "shift-jis") or eqlLoose(s, "shiftjis") or eqlLoose(s, "cp932") or eqlLoose(s, "ms932")) return .shift_jis;
        if (eqlLoose(s, "eucjp") or eqlLoose(s, "euc-jp") or eqlLoose(s, "euc_jp") or eqlLoose(s, "euc")) return .euc_jp;
        if (eqlLoose(s, "jis") or eqlLoose(s, "iso2022jp") or eqlLoose(s, "iso-2022-jp") or eqlLoose(s, "iso_2022_jp")) return .iso_2022_jp;
        if (eqlLoose(s, "utf16le") or eqlLoose(s, "utf-16le") or eqlLoose(s, "utf16") or eqlLoose(s, "utf-16")) return .utf16_le;
        if (eqlLoose(s, "utf16be") or eqlLoose(s, "utf-16be")) return .utf16_be;
        return null;
    }

    fn eqlLoose(a: []const u8, b: []const u8) bool {
        return std.ascii.eqlIgnoreCase(a, b);
    }
};

/// Automatically detects text encoding from raw file bytes.
pub fn detect(raw: []const u8) Encoding {
    if (raw.len >= 3 and raw[0] == 0xEF and raw[1] == 0xBB and raw[2] == 0xBF) {
        return .utf8_bom;
    }
    if (raw.len >= 2) {
        if (raw[0] == 0xFF and raw[1] == 0xFE) return .utf16_le;
        if (raw[0] == 0xFE and raw[1] == 0xFF) return .utf16_be;
    }

    // Check for ISO-2022-JP escape sequences (ESC $ B, ESC $ @, ESC ( J, ESC ( I)
    if (hasIso2022JpEscape(raw)) {
        return .iso_2022_jp;
    }

    // Heuristic UTF-16LE / UTF-16BE detection without BOM (e.g., ASCII characters interleaved with 0x00)
    if (raw.len >= 4 and (raw.len % 2) == 0) {
        var even_zeros: usize = 0;
        var odd_zeros: usize = 0;
        const sample = @min(raw.len, 512);
        var i: usize = 0;
        while (i + 1 < sample) : (i += 2) {
            if (raw[i] == 0 and raw[i + 1] != 0) even_zeros += 1;
            if (raw[i + 1] == 0 and raw[i] != 0) odd_zeros += 1;
        }
        const pairs = sample / 2;
        if (odd_zeros * 2 >= pairs and even_zeros == 0) return .utf16_le;
        if (even_zeros * 2 >= pairs and odd_zeros == 0) return .utf16_be;
    }

    // Valid UTF-8 check (including pure ASCII)
    if (std.unicode.utf8ValidateSlice(raw)) {
        return .utf8;
    }

    // Compare Shift_JIS (CP932) vs EUC-JP likelihood
    const sjis_score = scoreShiftJis(raw);
    const euc_score = scoreEucJp(raw);
    if (euc_score > sjis_score) {
        return .euc_jp;
    }
    return .shift_jis;
}

fn hasIso2022JpEscape(raw: []const u8) bool {
    var i: usize = 0;
    while (i + 2 < raw.len) : (i += 1) {
        if (raw[i] == 0x1B) {
            const b1 = raw[i + 1];
            const b2 = raw[i + 2];
            if (b1 == '$' and (b2 == 'B' or b2 == '@')) return true;
            if (b1 == '(' and (b2 == 'J' or b2 == 'I')) return true;
        }
    }
    return false;
}

fn scoreShiftJis(raw: []const u8) isize {
    var score: isize = 0;
    var i: usize = 0;
    while (i < raw.len) {
        const b = raw[i];
        if (b < 0x80) {
            i += 1;
        } else if ((b >= 0x81 and b <= 0x9F) or (b >= 0xE0 and b <= 0xFC)) {
            if (i + 1 < raw.len) {
                const t = raw[i + 1];
                if ((t >= 0x40 and t <= 0x7E) or (t >= 0x80 and t <= 0xFC)) {
                    const cp = lookupCp932(b, t);
                    if (cp != 0) {
                        // Hiragana (row 4: lead 0x82) and Katakana (row 5: lead 0x83) get strong bonus
                        score += if (b == 0x82 or b == 0x83 or b == 0x81) 4 else 2;
                        i += 2;
                        continue;
                    }
                }
            }
            score -= 5;
            i += 1;
        } else if (b >= 0xA1 and b <= 0xDF) {
            // Half-width Katakana
            score += 1;
            i += 1;
        } else {
            score -= 5;
            i += 1;
        }
    }
    return score;
}

fn scoreEucJp(raw: []const u8) isize {
    var score: isize = 0;
    var i: usize = 0;
    while (i < raw.len) {
        const b = raw[i];
        if (b < 0x80) {
            i += 1;
        } else if (b == 0x8E and i + 1 < raw.len and raw[i + 1] >= 0xA1 and raw[i + 1] <= 0xDF) {
            // JIS X 0201 half-width katakana in EUC-JP
            score += 2;
            i += 2;
        } else if (b >= 0xA1 and b <= 0xFE and i + 1 < raw.len and raw[i + 1] >= 0xA1 and raw[i + 1] <= 0xFE) {
            const cp = lookupJisRowCell(b - 0xA0, raw[i + 1] - 0xA0);
            if (cp != 0) {
                // Hiragana (0xA4) and Katakana (0xA5) in EUC-JP
                score += if (b == 0xA4 or b == 0xA5 or b == 0xA1) 4 else 2;
                i += 2;
                continue;
            }
            score -= 3;
            i += 2;
        } else {
            score -= 5;
            i += 1;
        }
    }
    return score;
}

fn lookupCp932(lead: u8, trail: u8) u16 {
    if (trail < 0x40 or trail > 0xFC or trail == 0x7F) return 0;
    const lead_idx: usize = if (lead >= 0x81 and lead <= 0x9F)
        lead - 0x81
    else if (lead >= 0xE0 and lead <= 0xFC)
        31 + (lead - 0xE0)
    else
        return 0;
    const trail_idx: usize = trail - 0x40;
    return table.CP932_TO_UTF16[lead_idx * 189 + trail_idx];
}

fn lookupJisRowCell(row: u8, cell: u8) u16 {
    if (row < 1 or row > 94 or cell < 1 or cell > 94) return 0;
    const lead: u8 = ((row - 1) >> 1) + (if (row <= 62) @as(u8, 0x81) else @as(u8, 0xC1));
    const trail: u8 = cell + (if ((row & 1) != 0)
        (if (cell <= 63) @as(u8, 0x3F) else @as(u8, 0x40))
    else
        @as(u8, 0x9E));
    return lookupCp932(lead, trail);
}

/// Decodes raw bytes in the specified `enc` into a newly allocated UTF-8 slice.
pub fn decodeToUtf8(allocator: std.mem.Allocator, raw: []const u8, enc: Encoding) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    switch (enc) {
        .utf8 => {
            try appendSanitizedUtf8(&out, raw);
        },
        .utf8_bom => {
            const body = if (raw.len >= 3 and raw[0] == 0xEF and raw[1] == 0xBB and raw[2] == 0xBF) raw[3..] else raw;
            try appendSanitizedUtf8(&out, body);
        },
        .shift_jis => {
            var i: usize = 0;
            while (i < raw.len) {
                const b = raw[i];
                if (b < 0x80) {
                    try out.append(b);
                    i += 1;
                } else if (b >= 0xA1 and b <= 0xDF) {
                    // Half-width Katakana U+FF61..U+FF9F
                    try appendCodepoint(&out, @as(u21, 0xFF61) + (b - 0xA1));
                    i += 1;
                } else if (((b >= 0x81 and b <= 0x9F) or (b >= 0xE0 and b <= 0xFC)) and i + 1 < raw.len) {
                    const cp = lookupCp932(b, raw[i + 1]);
                    if (cp != 0) {
                        try appendCodepoint(&out, cp);
                        i += 2;
                    } else {
                        try appendCodepoint(&out, 0xFFFD);
                        i += 1;
                    }
                } else {
                    try appendCodepoint(&out, 0xFFFD);
                    i += 1;
                }
            }
        },
        .euc_jp => {
            var i: usize = 0;
            while (i < raw.len) {
                const b = raw[i];
                if (b < 0x80) {
                    try out.append(b);
                    i += 1;
                } else if (b == 0x8E and i + 1 < raw.len and raw[i + 1] >= 0xA1 and raw[i + 1] <= 0xDF) {
                    try appendCodepoint(&out, @as(u21, 0xFF61) + (raw[i + 1] - 0xA1));
                    i += 2;
                } else if (b == 0x8F and i + 2 < raw.len) {
                    // JIS X 0212 3-byte sequence fallback
                    try appendCodepoint(&out, 0xFFFD);
                    i += 3;
                } else if (b >= 0xA1 and b <= 0xFE and i + 1 < raw.len and raw[i + 1] >= 0xA1 and raw[i + 1] <= 0xFE) {
                    const cp = lookupJisRowCell(b - 0xA0, raw[i + 1] - 0xA0);
                    try appendCodepoint(&out, if (cp != 0) cp else 0xFFFD);
                    i += 2;
                } else {
                    try appendCodepoint(&out, 0xFFFD);
                    i += 1;
                }
            }
        },
        .iso_2022_jp => {
            const Mode = enum { ascii, jis_x0208, kana };
            var mode: Mode = .ascii;
            var i: usize = 0;
            while (i < raw.len) {
                if (raw[i] == 0x1B and i + 2 < raw.len) {
                    const b1 = raw[i + 1];
                    const b2 = raw[i + 2];
                    if (b1 == '$' and (b2 == 'B' or b2 == '@')) {
                        mode = .jis_x0208;
                        i += 3;
                        continue;
                    } else if (b1 == '(' and (b2 == 'B' or b2 == 'J')) {
                        mode = .ascii;
                        i += 3;
                        continue;
                    } else if (b1 == '(' and b2 == 'I') {
                        mode = .kana;
                        i += 3;
                        continue;
                    }
                }
                switch (mode) {
                    .ascii => {
                        try out.append(raw[i]);
                        i += 1;
                    },
                    .kana => {
                        const b = raw[i];
                        if (b >= 0x21 and b <= 0x5F) {
                            try appendCodepoint(&out, @as(u21, 0xFF61) + (b - 0x21));
                        } else {
                            try out.append(b);
                        }
                        i += 1;
                    },
                    .jis_x0208 => {
                        if (raw[i] < 0x21 or raw[i] > 0x7E or i + 1 >= raw.len) {
                            // Control char such as CR/LF resets or passes through
                            if (raw[i] == '\r' or raw[i] == '\n') mode = .ascii;
                            try out.append(raw[i]);
                            i += 1;
                        } else {
                            const cp = lookupJisRowCell(raw[i] - 0x20, raw[i + 1] - 0x20);
                            try appendCodepoint(&out, if (cp != 0) cp else 0xFFFD);
                            i += 2;
                        }
                    },
                }
            }
        },
        .utf16_le => {
            var i: usize = if (raw.len >= 2 and raw[0] == 0xFF and raw[1] == 0xFE) 2 else 0;
            while (i + 1 < raw.len) {
                const w1 = @as(u16, raw[i]) | (@as(u16, raw[i + 1]) << 8);
                i += 2;
                if (w1 >= 0xD800 and w1 <= 0xDBFF and i + 1 < raw.len) {
                    const w2 = @as(u16, raw[i]) | (@as(u16, raw[i + 1]) << 8);
                    if (w2 >= 0xDC00 and w2 <= 0xDFFF) {
                        i += 2;
                        const cp: u21 = 0x10000 + ((@as(u21, w1 - 0xD800) << 10) | @as(u21, w2 - 0xDC00));
                        try appendCodepoint(&out, cp);
                        continue;
                    }
                }
                if (w1 >= 0xD800 and w1 <= 0xDFFF) {
                    try appendCodepoint(&out, 0xFFFD);
                } else {
                    try appendCodepoint(&out, w1);
                }
            }
        },
        .utf16_be => {
            var i: usize = if (raw.len >= 2 and raw[0] == 0xFE and raw[1] == 0xFF) 2 else 0;
            while (i + 1 < raw.len) {
                const w1 = (@as(u16, raw[i]) << 8) | @as(u16, raw[i + 1]);
                i += 2;
                if (w1 >= 0xD800 and w1 <= 0xDBFF and i + 1 < raw.len) {
                    const w2 = (@as(u16, raw[i]) << 8) | @as(u16, raw[i + 1]);
                    if (w2 >= 0xDC00 and w2 <= 0xDFFF) {
                        i += 2;
                        const cp: u21 = 0x10000 + ((@as(u21, w1 - 0xD800) << 10) | @as(u21, w2 - 0xDC00));
                        try appendCodepoint(&out, cp);
                        continue;
                    }
                }
                if (w1 >= 0xD800 and w1 <= 0xDFFF) {
                    try appendCodepoint(&out, 0xFFFD);
                } else {
                    try appendCodepoint(&out, w1);
                }
            }
        },
    }

    return out.toOwnedSlice();
}

/// Encodes internal UTF-8 text back into `enc` (with CRLF conversion if `crlf` is true).
pub fn encodeFromUtf8(allocator: std.mem.Allocator, utf8: []const u8, enc: Encoding, crlf: bool) ![]u8 {
    // First apply LF -> CRLF if requested
    var norm = std.ArrayList(u8).init(allocator);
    defer norm.deinit();
    if (crlf) {
        try norm.ensureTotalCapacity(utf8.len + utf8.len / 16);
        for (utf8) |b| {
            if (b == '\n') try norm.append('\r');
            try norm.append(b);
        }
    }
    const src = if (crlf) norm.items else utf8;

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    switch (enc) {
        .utf8 => {
            try out.appendSlice(src);
        },
        .utf8_bom => {
            try out.appendSlice("\xEF\xBB\xBF");
            try out.appendSlice(src);
        },
        .shift_jis => {
            var i: usize = 0;
            while (i < src.len) {
                const cp_len = nextCodepoint(src[i..]);
                const cp = cp_len.cp;
                i += cp_len.len;
                if (cp < 0x80) {
                    try out.append(@intCast(cp));
                } else if (cp >= 0xFF61 and cp <= 0xFF9F) {
                    try out.append(@intCast(0xA1 + (cp - 0xFF61)));
                } else if (unicodeToCp932(cp)) |pair| {
                    try out.append(pair.lead);
                    try out.append(pair.trail);
                } else {
                    try out.append('?');
                }
            }
        },
        .euc_jp => {
            var i: usize = 0;
            while (i < src.len) {
                const cp_len = nextCodepoint(src[i..]);
                const cp = cp_len.cp;
                i += cp_len.len;
                if (cp < 0x80) {
                    try out.append(@intCast(cp));
                } else if (cp >= 0xFF61 and cp <= 0xFF9F) {
                    try out.append(0x8E);
                    try out.append(@intCast(0xA1 + (cp - 0xFF61)));
                } else if (unicodeToJisRowCell(cp)) |rc| {
                    try out.append(0xA0 + rc.row);
                    try out.append(0xA0 + rc.cell);
                } else {
                    try out.append('?');
                }
            }
        },
        .iso_2022_jp => {
            const Mode = enum { ascii, jis_x0208, kana };
            var mode: Mode = .ascii;
            var i: usize = 0;
            while (i < src.len) {
                const cp_len = nextCodepoint(src[i..]);
                const cp = cp_len.cp;
                i += cp_len.len;
                if (cp < 0x80) {
                    if (mode != .ascii) {
                        try out.appendSlice("\x1b(B");
                        mode = .ascii;
                    }
                    try out.append(@intCast(cp));
                } else if (cp >= 0xFF61 and cp <= 0xFF9F) {
                    if (mode != .kana) {
                        try out.appendSlice("\x1b(I");
                        mode = .kana;
                    }
                    try out.append(@intCast(0x21 + (cp - 0xFF61)));
                } else if (unicodeToJisRowCell(cp)) |rc| {
                    if (mode != .jis_x0208) {
                        try out.appendSlice("\x1b$B");
                        mode = .jis_x0208;
                    }
                    try out.append(0x20 + rc.row);
                    try out.append(0x20 + rc.cell);
                } else {
                    if (mode != .ascii) {
                        try out.appendSlice("\x1b(B");
                        mode = .ascii;
                    }
                    try out.append('?');
                }
            }
            if (mode != .ascii) {
                try out.appendSlice("\x1b(B");
            }
        },
        .utf16_le => {
            try out.appendSlice("\xFF\xFE");
            var i: usize = 0;
            while (i < src.len) {
                const cp_len = nextCodepoint(src[i..]);
                const cp = cp_len.cp;
                i += cp_len.len;
                if (cp <= 0xFFFF) {
                    const u: u16 = @intCast(cp);
                    try out.append(@truncate(u));
                    try out.append(@truncate(u >> 8));
                } else {
                    const v = cp - 0x10000;
                    const hi: u16 = @intCast(0xD800 + (v >> 10));
                    const lo: u16 = @intCast(0xDC00 + (v & 0x3FF));
                    try out.append(@truncate(hi));
                    try out.append(@truncate(hi >> 8));
                    try out.append(@truncate(lo));
                    try out.append(@truncate(lo >> 8));
                }
            }
        },
        .utf16_be => {
            try out.appendSlice("\xFE\xFF");
            var i: usize = 0;
            while (i < src.len) {
                const cp_len = nextCodepoint(src[i..]);
                const cp = cp_len.cp;
                i += cp_len.len;
                if (cp <= 0xFFFF) {
                    const u: u16 = @intCast(cp);
                    try out.append(@truncate(u >> 8));
                    try out.append(@truncate(u));
                } else {
                    const v = cp - 0x10000;
                    const hi: u16 = @intCast(0xD800 + (v >> 10));
                    const lo: u16 = @intCast(0xDC00 + (v & 0x3FF));
                    try out.append(@truncate(hi >> 8));
                    try out.append(@truncate(hi));
                    try out.append(@truncate(lo >> 8));
                    try out.append(@truncate(lo));
                }
            }
        },
    }

    return out.toOwnedSlice();
}

fn appendSanitizedUtf8(out: *std.ArrayList(u8), raw: []const u8) !void {
    try out.ensureTotalCapacity(raw.len);
    var i: usize = 0;
    while (i < raw.len) {
        const b = raw[i];
        if (b < 0x80) {
            try out.append(b);
            i += 1;
            continue;
        }
        const seq_len = std.unicode.utf8ByteSequenceLength(b) catch {
            try appendCodepoint(out, 0xFFFD);
            i += 1;
            continue;
        };
        if (i + seq_len <= raw.len) {
            if (std.unicode.utf8Decode(raw[i .. i + seq_len])) |_| {
                try out.appendSlice(raw[i .. i + seq_len]);
                i += seq_len;
                continue;
            } else |_| {}
        }
        try appendCodepoint(out, 0xFFFD);
        i += 1;
    }
}

fn appendCodepoint(out: *std.ArrayList(u8), cp: u21) !void {
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(cp, &buf) catch return;
    try out.appendSlice(buf[0..len]);
}

fn nextCodepoint(s: []const u8) struct { cp: u21, len: usize } {
    if (s.len == 0) return .{ .cp = 0, .len = 0 };
    const seq_len = std.unicode.utf8ByteSequenceLength(s[0]) catch return .{ .cp = 0xFFFD, .len = 1 };
    if (s.len < seq_len) return .{ .cp = 0xFFFD, .len = 1 };
    const cp = std.unicode.utf8Decode(s[0..seq_len]) catch return .{ .cp = 0xFFFD, .len = 1 };
    return .{ .cp = cp, .len = seq_len };
}

fn unicodeToCp932(cp: u21) ?struct { lead: u8, trail: u8 } {
    if (cp > 0xFFFF or cp == 0) return null;
    // Handle common fullwidth wave dash / tilde variance (U+301C -> U+FF5E in CP932)
    const target: u16 = if (cp == 0x301C) 0xFF5E else if (cp == 0x2212) 0xFF0D else @intCast(cp);

    for (table.CP932_TO_UTF16, 0..) |entry, idx| {
        if (entry == target) {
            const lead_idx = idx / 189;
            const trail_idx = idx % 189;
            const lead: u8 = if (lead_idx < 31)
                @intCast(0x81 + lead_idx)
            else
                @intCast(0xE0 + (lead_idx - 31));
            const trail: u8 = @intCast(0x40 + trail_idx);
            return .{ .lead = lead, .trail = trail };
        }
    }
    return null;
}

fn unicodeToJisRowCell(cp: u21) ?struct { row: u8, cell: u8 } {
    const pair = unicodeToCp932(cp) orelse return null;
    // Convert SJIS lead/trail (within rows 1..94, i.e. lead 0x81..0x9F or 0xE0..0xEF) to JIS row/cell
    const lead_offset: u8 = if (pair.lead >= 0x81 and pair.lead <= 0x9F)
        pair.lead - 0x81
    else if (pair.lead >= 0xE0 and pair.lead <= 0xEF)
        31 + (pair.lead - 0xE0)
    else
        return null;

    const odd = pair.trail < 0x9F;
    const row: u8 = lead_offset * 2 + (if (odd) @as(u8, 1) else @as(u8, 2));
    if (row < 1 or row > 94) return null;

    const cell: u8 = if (odd)
        pair.trail - (if (pair.trail > 0x7F) @as(u8, 0x40) else @as(u8, 0x3F))
    else
        pair.trail - 0x9E;
    if (cell < 1 or cell > 94) return null;
    return .{ .row = row, .cell = cell };
}

test "Auto-detection and roundtrip conversion for UTF-8, Shift_JIS, EUC-JP, ISO-2022-JP, and UTF-16" {
    const alloc = std.testing.allocator;
    const sample_utf8 = "日本語テキスト編集 Test 123";

    for (Encoding.all) |enc| {
        const encoded = try encodeFromUtf8(alloc, sample_utf8, enc, false);
        defer alloc.free(encoded);

        const detected = detect(encoded);
        try std.testing.expectEqual(enc, detected);

        const decoded = try decodeToUtf8(alloc, encoded, enc);
        defer alloc.free(decoded);

        try std.testing.expectEqualStrings(sample_utf8, decoded);
    }
}
