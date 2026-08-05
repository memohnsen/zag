const std = @import("std");
const vaxis = @import("vaxis");
const editor = @import("editor/editor.zig");

const welcome_text = "Zag Editor -- Version 0.1.0";

pub fn refresh(
    vx: *vaxis.Vaxis,
    tty: *std.Io.Writer,
    document: *const editor.Editor,
) !void {
    const window = vx.window();
    window.clear();
    drawRows(window, document);

    var file_buf: [256]u8 = undefined;
    var cursor_buf: [256]u8 = undefined;
    try drawStatusBar(window, document, file_buf[0..], cursor_buf[0..]);

    const screen_x = document.cursor_x - document.col_offset;
    const screen_y = document.cursor_y - document.row_offset;
    window.showCursor(@intCast(screen_x), @intCast(screen_y));

    try vx.render(tty);
}

fn drawRows(window: vaxis.Window, document: *const editor.Editor) void {
    const text_height = window.height -| 1;
    for (0..text_height) |screen_row| {
        const file_row = document.row_offset + screen_row;

        if (file_row < document.rows.items.len) {
            const chars = document.rows.items[file_row].chars.items;
            const start = @min(document.col_offset, chars.len);
            printAt(window, chars[start..], screen_row, 0);
            continue;
        }

        if (document.rows.items.len == 0 and screen_row == text_height / 3) {
            drawWelcome(window, screen_row);
        } else {
            printAt(window, "~", screen_row, 0);
        }
    }
}

fn drawStatusBar(
    window: vaxis.Window,
    document: *const editor.Editor,
    file_buf: []u8,
    cursor_buf: []u8,
) !void {
    if (window.height == 0) {
        return;
    }

    const status_window = window.child(.{ .y_off = @intCast(window.height -| 1), .height = 1 });
    status_window.fill(.{ .style = .{ .reverse = true } });

    // Show filename and lines in file
    const file: []const u8 = if (document.filename) |name| name else "[No File]";
    const file_text = try std.fmt.bufPrint(file_buf, " {s} | {s} - {d} lines", .{ @tagName(document.mode), file, document.rows.items.len });
    _ = status_window.printSegment(.{ .text = file_text, .style = .{ .reverse = true } }, .{ .wrap = .none });

    // Show cursor position
    const cursor_text = try std.fmt.bufPrint(cursor_buf, "{d}:{d}", .{ document.cursor_y + 1, document.cursor_x + 1 });
    const text_width: u16 = @intCast(cursor_text.len);
    const text_col = status_window.width -| text_width;
    _ = status_window.printSegment(.{ .text = cursor_text, .style = .{ .reverse = true } }, .{ .wrap = .none, .col_offset = text_col });
}

fn drawWelcome(window: vaxis.Window, screen_row: usize) void {
    printAt(window, "~", screen_row, 0);

    const visible_len = @min(welcome_text.len, @as(usize, window.width));
    const padding = (@as(usize, window.width) - visible_len) / 2;
    printAt(window, welcome_text[0..visible_len], screen_row, padding);
}

fn printAt(
    window: vaxis.Window,
    text: []const u8,
    row: usize,
    col: usize,
) void {
    _ = window.printSegment(
        .{ .text = text },
        .{
            .row_offset = @intCast(row),
            .col_offset = @intCast(col),
            .wrap = .none,
        },
    );
}
