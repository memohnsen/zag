const std = @import("std");
const editor = @import("editor.zig");

const TerminalSize = struct {
    rows: usize,
    columns: usize,
};

pub fn getTerminalSize(io: std.Io) !TerminalSize {
    var window_size: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };

    const result = (try io.operate(.{ .device_io_control = .{ .file = .stdout(), .code = std.posix.T.IOCGWINSZ, .arg = &window_size } })).device_io_control;

    if (result < 0 or window_size.row == 0 or window_size.col == 0) {
        // you can apparently create your own random errors out of nowhere
        return error.UnableToGetTerminalSize;
    }

    return .{ .rows = @intCast(window_size.row), .columns = @intCast(window_size.col) };
}

pub fn drawRows(io: *std.Io.Writer, screen_rows: TerminalSize, document: *const editor.Editor) !void {
    const welcome_text = "Zag Editor -- Version 0.1.0";
    const welcome_len = @min(welcome_text.len, screen_rows.columns);
    var padding = (screen_rows.columns - welcome_len) / 2;
    const rows = screen_rows.rows;

    for (0..rows) |row| {
        if (row < document.rows.items.len) {
            const row_chars = document.rows.items[row].chars;
            const visible_length = @min(row_chars.len, screen_rows.columns);
            try io.writeAll(row_chars[0..visible_length]);
        } else if (row == rows / 3 and document.rows.items.len == 0) {
            if (padding > 0) {
                try io.writeAll("~");
                padding -= 1;
                try io.splatByteAll(' ', padding);
            }
            try io.writeAll(welcome_text[0..welcome_len]);
        } else {
            try io.writeAll("~");
        }
        try io.writeAll("\x1b[K");
        if (row < rows - 1) {
            try io.writeAll("\r\n");
        }
    }
}

pub fn clearScreen(io: std.Io) !void {
    try std.Io.File.writeStreamingAll(.stdout(), io, "\x1b[2J");
    try std.Io.File.writeStreamingAll(.stdout(), io, "\x1b[H");
    try std.Io.File.writeStreamingAll(.stdout(), io, "\x1b[?25h");
}

pub fn refreshScreen(io: std.Io, screen_rows: TerminalSize, gpa: std.mem.Allocator, cursor_x: usize, cursor_y: usize, document: *const editor.Editor) !void {
    var writer = std.Io.Writer.Allocating.init(gpa);
    defer writer.deinit();
    // esc sequence to hide cursor
    try writer.writer.writeAll("\x1b[?25l");
    // esc sequence to move to row 1 col 1
    try writer.writer.writeAll("\x1b[H");
    try drawRows(&writer.writer, screen_rows, document);
    // esc sequence to move to row col of cursor
    try writer.writer.print("\x1b[{d};{d}H", .{ cursor_y + 1, cursor_x + 1 });
    // esc sequence to show cursor
    try writer.writer.writeAll("\x1b[?25h");
    try std.Io.File.writeStreamingAll(.stdout(), io, writer.written());
}
