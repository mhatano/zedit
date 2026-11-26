# zedit

A compact, speedy, zero-dependency, multi-platform programmer's terminal text editor written in **Zig**.

## Highlights

- **Tiny & Instant**: Pure Zig stdlib with zero external dependencies. Compiles to a single static binary (~150–300 KB with `ReleaseSmall`) with millisecond startup.
- **Fast Text Engine**: Gap buffer with SIMD-accelerated line indexing, CRLF/LF preservation, UTF-8 navigation, and grouped multi-level Undo/Redo (`src/buffer.zig`).
- **True Multi-Platform**: Native POSIX (`termios` + `ioctl` + `SIGWINCH`) and Win32 Console VT backends (`src/terminal.zig`) — cross-compiles cleanly to Linux, macOS, and Windows out of the box.
- **Flicker-Free Rendering**: Double-buffered single-write ANSI TrueColor renderer with synchronized output (`?2026h`), line numbers, current-line highlight, selection, and matching bracket highlighting (`src/editor.zig`).
- **Syntax Highlighting**: Multi-line state-aware highlighter for **Zig**, **C/C++**, **Rust**, **Python**, **JS/TS**, **Go**, **JSON**, and **Markdown** (`src/syntax.zig`).
- **Incremental Search & Replace (with Regex)**: Live match highlighting powered by a built-in linear-time Thompson NFA / Pike VM regex engine (`src/regex.zig`), immune to catastrophic backtracking.
- **Multi-Tab Buffers & File Explorer**: Top clickable tab bar + collapsible workspace directory tree (`src/explorer.zig`) + SGR mouse click/drag/scroll + OSC 52 system clipboard sync.

## Building

Requires **Zig 0.14.x**.

```bash
# Compact release build (stripped)
zig build -Doptimize=ReleaseSmall

# Maximum speed release build
zig build -Doptimize=ReleaseFast

# Run unit tests
zig build test
```

### Cross-Compiling for Other Platforms

```bash
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl
zig build -Doptimize=ReleaseSmall -Dtarget=aarch64-linux-musl
zig build -Doptimize=ReleaseSmall -Dtarget=aarch64-macos
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-macos
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-windows
```

## Usage

```bash
./zig-out/bin/zedit [files or directory...]
```

## Keybindings

| Shortcut | Action |
|---|---|
| `Ctrl+S` | Save (or Save As if untitled) |
| `Ctrl+O` | Open file |
| `Ctrl+N` | New tab / buffer |
| `Ctrl+W` | Close active tab |
| `Ctrl+Q` | Quit (press twice if unsaved changes exist) |
| `Alt+Left` / `Alt+Right` | Previous / Next tab (`Ctrl+Tab`, `Alt+1..9` also supported) |
| `Ctrl+B` | Toggle file explorer sidebar |
| `Ctrl+E` | Focus / unfocus file explorer sidebar (`.` toggles dotfiles) |
| `Ctrl+F` | Incremental search (`Alt+R` Regex, `Alt+C` Case, `↑`/`↓`/`Enter` navigate) |
| `Ctrl+H` | Incremental search & replace (`Tab` switch field, `Enter` replace, `Alt+A` replace all) |
| `F3` / `Shift+F3` | Jump to next / previous search match |
| `Ctrl+G` | Go to `line` or `line:col` |
| `Ctrl+Z` / `Ctrl+Y` | Undo / Redo (`Ctrl+Shift+Z` also Redo) |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | Copy / Cut / Paste (with OSC 52 terminal clipboard sync) |
| `Ctrl+A` | Select all |
| `Ctrl+D` | Duplicate line or selection |
| `Ctrl+K` | Delete current line |
| `Shift+Arrows` / `Home` / `End` | Extend selection |
| `Ctrl+Left` / `Ctrl+Right` | Jump by word (`Ctrl+Shift+Left/Right` selects word) |
| `Ctrl+Backspace` | Delete previous word |
| `Tab` / `Shift+Tab` | Indent / Unindent (supports multi-line selections) |
| `F1` | Show quick shortcut reference in status bar |
