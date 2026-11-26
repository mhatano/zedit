const std = @import("std");

pub const Language = enum {
    plain,
    zig,
    c_cpp,
    rust,
    python,
    js_ts,
    go,
    json,
    markdown,

    pub fn name(self: Language) []const u8 {
        return switch (self) {
            .plain => "Plain Text",
            .zig => "Zig",
            .c_cpp => "C/C++",
            .rust => "Rust",
            .python => "Python",
            .js_ts => "JS/TS",
            .go => "Go",
            .json => "JSON",
            .markdown => "Markdown",
        };
    }

    pub fn detect(path: ?[]const u8) Language {
        const p = path orelse return .plain;
        const ext = std.fs.path.extension(p);
        if (ext.len == 0) return .plain;

        if (eqlCI(ext, ".zig") or eqlCI(ext, ".zon")) return .zig;
        if (eqlCI(ext, ".c") or eqlCI(ext, ".h") or eqlCI(ext, ".cpp") or
            eqlCI(ext, ".cc") or eqlCI(ext, ".cxx") or eqlCI(ext, ".hpp") or
            eqlCI(ext, ".hh") or eqlCI(ext, ".hxx")) return .c_cpp;
        if (eqlCI(ext, ".rs")) return .rust;
        if (eqlCI(ext, ".py") or eqlCI(ext, ".pyi")) return .python;
        if (eqlCI(ext, ".js") or eqlCI(ext, ".jsx") or eqlCI(ext, ".mjs") or
            eqlCI(ext, ".cjs") or eqlCI(ext, ".ts") or eqlCI(ext, ".tsx")) return .js_ts;
        if (eqlCI(ext, ".go")) return .go;
        if (eqlCI(ext, ".json") or eqlCI(ext, ".jsonc")) return .json;
        if (eqlCI(ext, ".md") or eqlCI(ext, ".markdown")) return .markdown;

        return .plain;
    }

    fn eqlCI(a: []const u8, b: []const u8) bool {
        return std.ascii.eqlIgnoreCase(a, b);
    }
};

pub const TokenKind = enum(u8) {
    normal,
    keyword,
    type_name,
    string,
    number,
    comment,
    builtin,
    function,
    constant,
    operator,
    heading,
};

pub const LineState = enum(u8) {
    normal,
    block_comment,
    triple_double_quote,
    triple_single_quote,
    backtick_string,
    md_code_fence,
};

pub const Rgb = struct { r: u8, g: u8, b: u8 };

pub fn tokenColor(kind: TokenKind) Rgb {
    // High-contrast dark theme (Catppuccin Mocha / Tokyo Night inspired)
    return switch (kind) {
        .normal => .{ .r = 205, .g = 214, .b = 244 }, // #cdd6f4
        .keyword => .{ .r = 203, .g = 166, .b = 247 }, // #cba6f7 (mauve)
        .type_name => .{ .r = 249, .g = 226, .b = 175 }, // #f9e2af (yellow)
        .string => .{ .r = 166, .g = 227, .b = 161 }, // #a6e3a1 (green)
        .number => .{ .r = 250, .g = 179, .b = 135 }, // #fab387 (peach)
        .comment => .{ .r = 108, .g = 112, .b = 134 }, // #6c7086 (overlay0)
        .builtin => .{ .r = 243, .g = 139, .b = 168 }, // #f38ba8 (red/pink)
        .function => .{ .r = 137, .g = 180, .b = 250 }, // #89b4fa (blue)
        .constant => .{ .r = 250, .g = 179, .b = 135 }, // #fab387 (peach)
        .operator => .{ .r = 137, .g = 220, .b = 235 }, // #89dceb (sky)
        .heading => .{ .r = 137, .g = 180, .b = 250 }, // #89b4fa (blue)
    };
}

const zig_keywords = [_][]const u8{
    "addrspace", "align",       "allowzero", "and",        "anyframe",  "anytype",
    "asm",       "async",       "await",     "break",      "callconv",  "catch",
    "comptime",  "const",       "continue",  "defer",      "else",      "enum",
    "errdefer",  "error",       "export",    "extern",     "fn",        "for",
    "if",        "inline",      "linksection", "noalias",  "noinline",  "nosuspend",
    "opaque",    "or",          "orelse",    "packed",     "pub",       "resume",
    "return",    "struct",      "suspend",   "switch",     "test",      "threadlocal",
    "try",       "union",       "unreachable", "usingnamespace", "var", "volatile",
    "while",
};

const zig_types = [_][]const u8{
    "bool",     "f16",     "f32",       "f64",       "f80",       "f128",
    "i8",       "i16",     "i32",       "i64",       "i128",      "isize",
    "u8",       "u16",     "u32",       "u64",       "u128",      "usize",
    "c_char",   "c_short", "c_ushort",  "c_int",     "c_uint",    "c_long",
    "c_ulong",  "c_longlong", "c_ulonglong", "c_longdouble", "anyopaque",
    "void",     "noreturn", "type",     "anyerror",  "comptime_int", "comptime_float",
};

const zig_constants = [_][]const u8{ "true", "false", "null", "undefined" };

const c_keywords = [_][]const u8{
    "alignas",  "alignof",  "asm",       "auto",      "break",     "case",
    "catch",    "class",    "co_await",  "co_return", "co_yield",  "concept",
    "const",    "consteval","constexpr", "constinit", "continue",  "decltype",
    "default",  "delete",   "do",        "else",      "enum",      "explicit",
    "export",   "extern",   "final",     "for",       "friend",    "goto",
    "if",       "inline",   "mutable",   "namespace", "new",       "noexcept",
    "operator", "override", "private",   "protected", "public",    "register",
    "requires", "restrict", "return",    "sizeof",    "static",    "static_assert",
    "struct",   "switch",   "template",  "this",      "thread_local", "throw",
    "try",      "typedef",  "typeid",    "typename",  "union",     "using",
    "virtual",  "volatile", "while",
};

const c_types = [_][]const u8{
    "bool",     "char",     "char8_t",   "char16_t",  "char32_t",  "double",
    "float",    "int",      "int8_t",    "int16_t",   "int32_t",   "int64_t",
    "long",     "ptrdiff_t","short",     "signed",    "size_t",    "ssize_t",
    "uint8_t",  "uint16_t", "uint32_t",  "uint64_t",  "uintptr_t", "unsigned",
    "void",     "wchar_t",  "FILE",      "string",    "vector",
};

const c_constants = [_][]const u8{ "true", "false", "NULL", "nullptr", "EOF" };

const rust_keywords = [_][]const u8{
    "as",       "async",    "await",     "break",     "const",     "continue",
    "crate",    "dyn",      "else",      "enum",      "extern",    "fn",
    "for",      "if",       "impl",      "in",        "let",       "loop",
    "match",    "mod",      "move",      "mut",       "pub",       "ref",
    "return",   "self",     "Self",      "static",    "struct",    "super",
    "trait",    "type",     "unsafe",    "use",       "where",     "while",
};

const rust_types = [_][]const u8{
    "bool",     "char",     "f32",       "f64",       "i8",        "i16",
    "i32",      "i64",      "i128",      "isize",     "str",       "u8",
    "u16",      "u32",      "u64",       "u128",      "usize",     "String",
    "Vec",      "Option",   "Result",    "Box",       "Rc",        "Arc",
    "HashMap",  "HashSet",
};

const rust_constants = [_][]const u8{ "true", "false", "Some", "None", "Ok", "Err" };

const py_keywords = [_][]const u8{
    "and",      "as",       "assert",    "async",     "await",     "break",
    "class",    "continue", "def",       "del",       "elif",      "else",
    "except",   "finally",  "for",       "from",      "global",    "if",
    "import",   "in",       "is",        "lambda",    "match",     "case",
    "nonlocal", "not",      "or",        "pass",      "raise",     "return",
    "try",      "while",    "with",      "yield",
};

const py_types = [_][]const u8{
    "bool",     "bytes",    "bytearray", "complex",   "dict",      "float",
    "frozenset","int",      "list",      "object",    "set",       "str",
    "tuple",    "type",     "Any",       "List",      "Dict",      "Optional",
};

const py_builtins = [_][]const u8{
    "abs",      "all",      "any",       "chr",       "enumerate", "filter",
    "getattr",  "hasattr",  "input",     "isinstance","len",       "map",
    "max",      "min",      "open",      "ord",       "print",     "range",
    "repr",     "reversed", "round",     "setattr",   "sorted",    "sum",
    "super",    "zip",      "self",      "cls",
};

const py_constants = [_][]const u8{ "True", "False", "None", "NotImplemented", "Ellipsis" };

const js_keywords = [_][]const u8{
    "abstract", "as",       "async",     "await",     "break",     "case",
    "catch",    "class",    "const",     "continue",  "debugger",  "declare",
    "default",  "delete",   "do",        "else",      "enum",      "export",
    "extends",  "finally",  "for",       "from",      "function",  "get",
    "if",       "implements","import",   "in",        "instanceof","interface",
    "is",       "keyof",    "let",       "module",    "namespace", "new",
    "of",       "override", "private",   "protected", "public",    "readonly",
    "return",   "set",      "static",    "super",     "switch",    "this",
    "throw",    "try",      "type",      "typeof",    "var",       "void",
    "while",    "with",     "yield",
};

const js_types = [_][]const u8{
    "any",      "bigint",   "boolean",   "never",     "number",    "object",
    "string",   "symbol",   "unknown",   "Array",     "Date",      "Error",
    "Function", "Map",      "Object",    "Promise",   "RegExp",    "Set",
    "Record",   "Partial",  "Required",  "Readonly",  "Omit",      "Pick",
};

const js_constants = [_][]const u8{ "true", "false", "null", "undefined", "NaN", "Infinity" };

const go_keywords = [_][]const u8{
    "break",    "case",     "chan",      "const",     "continue",  "default",
    "defer",    "else",     "fallthrough","for",      "func",      "go",
    "goto",     "if",       "import",    "interface", "map",       "package",
    "range",    "return",   "select",    "struct",    "switch",    "type",
    "var",
};

const go_types = [_][]const u8{
    "any",      "bool",     "byte",      "comparable","complex64", "complex128",
    "error",    "float32",  "float64",   "int",       "int8",      "int16",
    "int32",    "int64",    "rune",      "string",    "uint",      "uint8",
    "uint16",   "uint32",   "uint64",    "uintptr",
};

const go_builtins = [_][]const u8{
    "append",   "cap",      "clear",     "close",     "complex",   "copy",
    "delete",   "imag",     "len",       "make",      "max",       "min",
    "new",      "panic",    "print",     "println",   "real",      "recover",
};

const go_constants = [_][]const u8{ "true", "false", "nil", "iota" };

fn containsWord(list: []const []const u8, word: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, word)) return true;
    }
    return false;
}

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_' or c == '$';
}

fn isIdentCont(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '$';
}

pub fn highlightLine(
    lang: Language,
    line: []const u8,
    in_state: LineState,
    out: []TokenKind,
) LineState {
    std.debug.assert(out.len == line.len);
    @memset(out, .normal);

    return switch (lang) {
        .plain => .normal,
        .json => highlightJson(line, in_state, out),
        .markdown => highlightMarkdown(line, in_state, out),
        .python => highlightPython(line, in_state, out),
        .zig, .c_cpp, .rust, .js_ts, .go => highlightCLike(lang, line, in_state, out),
    };
}

fn highlightJson(line: []const u8, in_state: LineState, out: []TokenKind) LineState {
    var state = in_state;
    var i: usize = 0;

    if (state == .block_comment) {
        while (i < line.len) : (i += 1) {
            out[i] = .comment;
            if (line[i] == '*' and i + 1 < line.len and line[i + 1] == '/') {
                out[i + 1] = .comment;
                i += 2;
                state = .normal;
                break;
            }
        }
        if (state == .block_comment) return .block_comment;
    }

    while (i < line.len) {
        const c = line[i];
        if (c == '/' and i + 1 < line.len and line[i + 1] == '/') {
            @memset(out[i..], .comment);
            return .normal;
        }
        if (c == '/' and i + 1 < line.len and line[i + 1] == '*') {
            out[i] = .comment;
            out[i + 1] = .comment;
            i += 2;
            state = .block_comment;
            while (i < line.len) : (i += 1) {
                out[i] = .comment;
                if (line[i] == '*' and i + 1 < line.len and line[i + 1] == '/') {
                    out[i + 1] = .comment;
                    i += 2;
                    state = .normal;
                    break;
                }
            }
            if (state == .block_comment) return .block_comment;
            continue;
        }
        if (c == '"') {
            const start = i;
            i += 1;
            while (i < line.len) : (i += 1) {
                if (line[i] == '\\' and i + 1 < line.len) {
                    i += 1;
                    continue;
                }
                if (line[i] == '"') {
                    i += 1;
                    break;
                }
            }
            // Check if followed by ':' -> JSON key!
            var look = i;
            while (look < line.len and (line[look] == ' ' or line[look] == '\t')) look += 1;
            const kind: TokenKind = if (look < line.len and line[look] == ':') .function else .string;
            @memset(out[start..i], kind);
            continue;
        }
        if (c == '-' or std.ascii.isDigit(c)) {
            if (c == '-' and (i + 1 >= line.len or !std.ascii.isDigit(line[i + 1]))) {
                out[i] = .operator;
                i += 1;
                continue;
            }
            const start = i;
            i += 1;
            while (i < line.len and (std.ascii.isDigit(line[i]) or line[i] == '.' or line[i] == 'e' or line[i] == 'E' or line[i] == '+' or line[i] == '-')) {
                i += 1;
            }
            @memset(out[start..i], .number);
            continue;
        }
        if (std.ascii.isAlphabetic(c)) {
            const start = i;
            while (i < line.len and std.ascii.isAlphabetic(line[i])) i += 1;
            const word = line[start..i];
            if (std.mem.eql(u8, word, "true") or std.mem.eql(u8, word, "false") or std.mem.eql(u8, word, "null")) {
                @memset(out[start..i], .constant);
            }
            continue;
        }
        if (c == ':' or c == ',' or c == '{' or c == '}' or c == '[' or c == ']') {
            out[i] = .operator;
        }
        i += 1;
    }
    return state;
}

fn highlightMarkdown(line: []const u8, in_state: LineState, out: []TokenKind) LineState {
    var trimmed_start: usize = 0;
    while (trimmed_start < line.len and (line[trimmed_start] == ' ' or line[trimmed_start] == '\t')) {
        trimmed_start += 1;
    }
    const rest = line[trimmed_start..];

    if (std.mem.startsWith(u8, rest, "```") or std.mem.startsWith(u8, rest, "~~~")) {
        @memset(out, .comment);
        return if (in_state == .md_code_fence) .normal else .md_code_fence;
    }
    if (in_state == .md_code_fence) {
        @memset(out, .string);
        return .md_code_fence;
    }

    if (rest.len > 0 and rest[0] == '#') {
        @memset(out, .heading);
        return .normal;
    }
    if (rest.len > 0 and rest[0] == '>') {
        @memset(out, .comment);
        return .normal;
    }
    if (rest.len >= 2 and (rest[0] == '-' or rest[0] == '*' or rest[0] == '+') and rest[1] == ' ') {
        out[trimmed_start] = .keyword;
    }

    var i: usize = 0;
    while (i < line.len) {
        if (line[i] == '`') {
            const start = i;
            i += 1;
            while (i < line.len and line[i] != '`') i += 1;
            if (i < line.len) i += 1;
            @memset(out[start..i], .string);
            continue;
        }
        if (line[i] == '*' and i + 1 < line.len and line[i + 1] == '*') {
            const start = i;
            i += 2;
            while (i + 1 < line.len and !(line[i] == '*' and line[i + 1] == '*')) i += 1;
            if (i + 1 < line.len) i += 2 else i = line.len;
            @memset(out[start..i], .keyword);
            continue;
        }
        if (line[i] == '[') {
            const start = i;
            i += 1;
            while (i < line.len and line[i] != ']') i += 1;
            if (i < line.len) {
                i += 1;
                @memset(out[start..i], .function);
                if (i < line.len and line[i] == '(') {
                    const ustart = i;
                    while (i < line.len and line[i] != ')') i += 1;
                    if (i < line.len) i += 1;
                    @memset(out[ustart..i], .type_name);
                }
                continue;
            }
        }
        i += 1;
    }

    return .normal;
}

fn highlightPython(line: []const u8, in_state: LineState, out: []TokenKind) LineState {
    var state = in_state;
    var i: usize = 0;

    if (state == .triple_double_quote or state == .triple_single_quote) {
        const q: u8 = if (state == .triple_double_quote) '"' else '\'';
        while (i < line.len) : (i += 1) {
            out[i] = .string;
            if (line[i] == '\\' and i + 1 < line.len) {
                i += 1;
                out[i] = .string;
                continue;
            }
            if (i + 2 < line.len and line[i] == q and line[i + 1] == q and line[i + 2] == q) {
                out[i + 1] = .string;
                out[i + 2] = .string;
                i += 3;
                state = .normal;
                break;
            }
        }
        if (state != .normal) return state;
    }

    while (i < line.len) {
        const c = line[i];

        if (c == '#') {
            @memset(out[i..], .comment);
            return .normal;
        }

        if (c == '@') {
            const start = i;
            i += 1;
            while (i < line.len and (isIdentCont(line[i]) or line[i] == '.')) i += 1;
            @memset(out[start..i], .builtin);
            continue;
        }

        if (c == '"' or c == '\'') {
            if (i + 2 < line.len and line[i + 1] == c and line[i + 2] == c) {
                const target_state: LineState = if (c == '"') .triple_double_quote else .triple_single_quote;
                out[i] = .string;
                out[i + 1] = .string;
                out[i + 2] = .string;
                i += 3;
                state = target_state;
                while (i < line.len) : (i += 1) {
                    out[i] = .string;
                    if (line[i] == '\\' and i + 1 < line.len) {
                        i += 1;
                        out[i] = .string;
                        continue;
                    }
                    if (i + 2 < line.len and line[i] == c and line[i + 1] == c and line[i + 2] == c) {
                        out[i + 1] = .string;
                        out[i + 2] = .string;
                        i += 3;
                        state = .normal;
                        break;
                    }
                }
                if (state != .normal) return state;
                continue;
            }
            const start = i;
            i += 1;
            while (i < line.len) : (i += 1) {
                if (line[i] == '\\' and i + 1 < line.len) {
                    i += 1;
                    continue;
                }
                if (line[i] == c) {
                    i += 1;
                    break;
                }
            }
            @memset(out[start..i], .string);
            continue;
        }

        if (std.ascii.isDigit(c)) {
            const start = i;
            i = scanNumber(line, i);
            @memset(out[start..i], .number);
            continue;
        }

        if (isIdentStart(c)) {
            const start = i;
            while (i < line.len and isIdentCont(line[i])) i += 1;
            const word = line[start..i];
            const kind: TokenKind = if (containsWord(&py_keywords, word))
                .keyword
            else if (containsWord(&py_constants, word))
                .constant
            else if (containsWord(&py_types, word))
                .type_name
            else if (containsWord(&py_builtins, word))
                .builtin
            else if (i < line.len and line[i] == '(')
                .function
            else
                .normal;
            @memset(out[start..i], kind);
            continue;
        }

        if (isOperatorChar(c)) {
            out[i] = .operator;
        }
        i += 1;
    }

    return .normal;
}

fn highlightCLike(lang: Language, line: []const u8, in_state: LineState, out: []TokenKind) LineState {
    var state = in_state;
    var i: usize = 0;

    // Handle multi-line states carried from previous line
    if (state == .block_comment) {
        while (i < line.len) : (i += 1) {
            out[i] = .comment;
            if (line[i] == '*' and i + 1 < line.len and line[i + 1] == '/') {
                out[i + 1] = .comment;
                i += 2;
                state = .normal;
                break;
            }
        }
        if (state == .block_comment) return .block_comment;
    } else if (state == .backtick_string) {
        while (i < line.len) : (i += 1) {
            out[i] = .string;
            if (lang == .js_ts and line[i] == '\\' and i + 1 < line.len) {
                i += 1;
                out[i] = .string;
                continue;
            }
            if (line[i] == '`') {
                i += 1;
                state = .normal;
                break;
            }
        }
        if (state == .backtick_string) return .backtick_string;
    }

    // C/C++ preprocessor directive on first non-whitespace char
    if (lang == .c_cpp and i == 0) {
        var ws: usize = 0;
        while (ws < line.len and (line[ws] == ' ' or line[ws] == '\t')) ws += 1;
        if (ws < line.len and line[ws] == '#') {
            var end = ws + 1;
            while (end < line.len and (line[end] == ' ' or line[end] == '\t')) end += 1;
            while (end < line.len and std.ascii.isAlphabetic(line[end])) end += 1;
            @memset(out[ws..end], .builtin);
            i = end;
        }
    }

    while (i < line.len) {
        const c = line[i];

        // Zig multiline string literal `\\...`
        if (lang == .zig and c == '\\' and i + 1 < line.len and line[i + 1] == '\\') {
            @memset(out[i..], .string);
            return .normal;
        }

        // Line comment //
        if (c == '/' and i + 1 < line.len and line[i + 1] == '/') {
            @memset(out[i..], .comment);
            return .normal;
        }

        // Block comment /* ... */ (not in Zig)
        if (lang != .zig and c == '/' and i + 1 < line.len and line[i + 1] == '*') {
            out[i] = .comment;
            out[i + 1] = .comment;
            i += 2;
            state = .block_comment;
            while (i < line.len) : (i += 1) {
                out[i] = .comment;
                if (line[i] == '*' and i + 1 < line.len and line[i + 1] == '/') {
                    out[i + 1] = .comment;
                    i += 2;
                    state = .normal;
                    break;
                }
            }
            if (state == .block_comment) return .block_comment;
            continue;
        }

        // Zig builtins `@import`, `@as`, etc.
        if (lang == .zig and c == '@' and i + 1 < line.len and isIdentStart(line[i + 1])) {
            const start = i;
            i += 1;
            while (i < line.len and isIdentCont(line[i])) i += 1;
            @memset(out[start..i], .builtin);
            continue;
        }

        // Rust attributes `#[...]` or `#![...]`
        if (lang == .rust and c == '#' and i + 1 < line.len and (line[i + 1] == '[' or line[i + 1] == '!')) {
            const start = i;
            while (i < line.len and line[i] != ']') i += 1;
            if (i < line.len) i += 1;
            @memset(out[start..i], .builtin);
            continue;
        }

        // Backtick strings (Go raw strings / JS template literals)
        if ((lang == .js_ts or lang == .go) and c == '`') {
            out[i] = .string;
            i += 1;
            state = .backtick_string;
            while (i < line.len) : (i += 1) {
                out[i] = .string;
                if (lang == .js_ts and line[i] == '\\' and i + 1 < line.len) {
                    i += 1;
                    out[i] = .string;
                    continue;
                }
                if (line[i] == '`') {
                    i += 1;
                    state = .normal;
                    break;
                }
            }
            if (state == .backtick_string) return .backtick_string;
            continue;
        }

        // Quoted strings & chars
        if (c == '"' or (c == '\'' and lang != .rust)) {
            const start = i;
            i += 1;
            while (i < line.len) : (i += 1) {
                if (line[i] == '\\' and i + 1 < line.len) {
                    i += 1;
                    continue;
                }
                if (line[i] == c) {
                    i += 1;
                    break;
                }
            }
            @memset(out[start..i], .string);
            continue;
        }

        // Rust char literal vs lifetime `'a`
        if (lang == .rust and c == '\'') {
            if (i + 2 < line.len and line[i + 1] == '\\') {
                const start = i;
                i += 2;
                while (i < line.len and line[i] != '\'') i += 1;
                if (i < line.len) i += 1;
                @memset(out[start..i], .string);
                continue;
            } else if (i + 2 < line.len and line[i + 2] == '\'') {
                @memset(out[i .. i + 3], .string);
                i += 3;
                continue;
            } else if (i + 1 < line.len and isIdentStart(line[i + 1])) {
                const start = i;
                i += 1;
                while (i < line.len and isIdentCont(line[i])) i += 1;
                @memset(out[start..i], .type_name);
                continue;
            }
        }

        // Numbers
        if (std.ascii.isDigit(c)) {
            const start = i;
            i = scanNumber(line, i);
            @memset(out[start..i], .number);
            continue;
        }

        // Identifiers / Keywords / Types / Functions
        if (isIdentStart(c)) {
            const start = i;
            while (i < line.len and isIdentCont(line[i])) i += 1;
            const word = line[start..i];
            const is_rust_macro = (lang == .rust and i < line.len and line[i] == '!');
            const kind = classifyWord(lang, word, i < line.len and line[i] == '(', is_rust_macro);
            if (is_rust_macro) {
                i += 1;
            }
            @memset(out[start..i], kind);
            continue;
        }

        if (isOperatorChar(c)) {
            out[i] = .operator;
        }
        i += 1;
    }

    return .normal;
}

fn classifyWord(lang: Language, word: []const u8, followed_by_paren: bool, is_rust_macro: bool) TokenKind {
    if (is_rust_macro) return .builtin;

    switch (lang) {
        .zig => {
            if (containsWord(&zig_keywords, word)) return .keyword;
            if (containsWord(&zig_types, word)) return .type_name;
            if (containsWord(&zig_constants, word)) return .constant;
            // Arbitrary bit-width Zig ints like u7, i24
            if (word.len >= 2 and (word[0] == 'u' or word[0] == 'i') and allDigits(word[1..])) return .type_name;
        },
        .c_cpp => {
            if (containsWord(&c_keywords, word)) return .keyword;
            if (containsWord(&c_types, word)) return .type_name;
            if (containsWord(&c_constants, word)) return .constant;
        },
        .rust => {
            if (containsWord(&rust_keywords, word)) return .keyword;
            if (containsWord(&rust_types, word)) return .type_name;
            if (containsWord(&rust_constants, word)) return .constant;
        },
        .js_ts => {
            if (containsWord(&js_keywords, word)) return .keyword;
            if (containsWord(&js_types, word)) return .type_name;
            if (containsWord(&js_constants, word)) return .constant;
        },
        .go => {
            if (containsWord(&go_keywords, word)) return .keyword;
            if (containsWord(&go_types, word)) return .type_name;
            if (containsWord(&go_builtins, word)) return .builtin;
            if (containsWord(&go_constants, word)) return .constant;
        },
        else => {},
    }

    if (followed_by_paren) return .function;
    if (word.len >= 2 and std.ascii.isUpper(word[0]) and hasLower(word[1..])) return .type_name;
    return .normal;
}

fn allDigits(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

fn hasLower(s: []const u8) bool {
    for (s) |c| {
        if (std.ascii.isLower(c)) return true;
    }
    return false;
}

fn scanNumber(line: []const u8, start: usize) usize {
    var i = start;
    if (line[i] == '0' and i + 1 < line.len and (line[i + 1] == 'x' or line[i + 1] == 'X' or line[i + 1] == 'b' or line[i + 1] == 'B' or line[i + 1] == 'o' or line[i + 1] == 'O')) {
        i += 2;
        while (i < line.len and (std.ascii.isHex(line[i]) or line[i] == '_')) i += 1;
        return i;
    }
    while (i < line.len and (std.ascii.isDigit(line[i]) or line[i] == '_')) i += 1;
    if (i < line.len and line[i] == '.' and i + 1 < line.len and std.ascii.isDigit(line[i + 1])) {
        i += 1;
        while (i < line.len and (std.ascii.isDigit(line[i]) or line[i] == '_')) i += 1;
    }
    if (i < line.len and (line[i] == 'e' or line[i] == 'E')) {
        i += 1;
        if (i < line.len and (line[i] == '+' or line[i] == '-')) i += 1;
        while (i < line.len and (std.ascii.isDigit(line[i]) or line[i] == '_')) i += 1;
    }
    // Optional numeric suffix (u32, f64, UL, etc.)
    while (i < line.len and std.ascii.isAlphanumeric(line[i])) i += 1;
    return i;
}

fn isOperatorChar(c: u8) bool {
    return switch (c) {
        '+', '-', '*', '/', '%', '=', '!', '<', '>', '&', '|', '^', '~', '?', ':' => true,
        else => false,
    };
}

test "Syntax highlighting for Zig, Python, C, and JSON" {
    var tokens: [64]TokenKind = undefined;

    const zig_line = "pub fn main() !void { const x: u32 = 42; }";
    const s1 = highlightLine(.zig, zig_line, .normal, tokens[0..zig_line.len]);
    try std.testing.expectEqual(LineState.normal, s1);
    try std.testing.expectEqual(TokenKind.keyword, tokens[0]); // pub
    try std.testing.expectEqual(TokenKind.function, tokens[7]); // main
    try std.testing.expectEqual(TokenKind.type_name, tokens[15]); // void
    try std.testing.expectEqual(TokenKind.number, tokens[37]); // 42

    const c_line = "int x = /* multi";
    const s2 = highlightLine(.c_cpp, c_line, .normal, tokens[0..c_line.len]);
    try std.testing.expectEqual(LineState.block_comment, s2);
    const c_line2 = "still comment */ 10;";
    const s3 = highlightLine(.c_cpp, c_line2, s2, tokens[0..c_line2.len]);
    try std.testing.expectEqual(LineState.normal, s3);
    try std.testing.expectEqual(TokenKind.comment, tokens[0]);
    try std.testing.expectEqual(TokenKind.number, tokens[17]);

    const json_line = "{\"name\": \"zedit\", \"fast\": true}";
    _ = highlightLine(.json, json_line, .normal, tokens[0..json_line.len]);
    try std.testing.expectEqual(TokenKind.function, tokens[1]); // key
    try std.testing.expectEqual(TokenKind.string, tokens[9]); // value
    try std.testing.expectEqual(TokenKind.constant, tokens[26]); // true
}
