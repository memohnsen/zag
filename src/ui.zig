const std = @import("std");
const vaxis = @import("vaxis");

const editor = @import("editor.zig");

const welcome_text = "Zag Editor -- Version 0.1.0";

pub fn refresh(
    vx: *vaxis.Vaxis,
    tty: *std.Io.Writer,
    document: *const editor.Editor,
) !void {
    const window = vx.window();
    window.clear();
    drawRows(window, document);

    const screen_x = document.cursor_x - document.col_offset;
    const screen_y = document.cursor_y - document.row_offset;
    window.showCursor(@intCast(screen_x), @intCast(screen_y));

    try vx.render(tty);
}

fn drawRows(window: vaxis.Window, document: *const editor.Editor) void {
    for (0..window.height) |screen_row| {
        const file_row = document.row_offset + screen_row;

        if (file_row < document.rows.items.len) {
            const chars = document.rows.items[file_row].chars;
            const start = @min(document.col_offset, chars.len);
            printAt(window, chars[start..], screen_row, 0);
            continue;
        }

        if (document.rows.items.len == 0 and screen_row == window.height / 3) {
            drawWelcome(window, screen_row);
        } else {
            printAt(window, "~", screen_row, 0);
        }
    }
}

fn drawWelcome(window: vaxis.Window, screen_row: usize) void {
    printAt(window, "~", screen_row, 0);

    const visible_len = @min(welcome_text.len, @as(usize, window.width));
    const padding = (@as(usize, window.width) - visible_len) / 2;
    printAt(window, welcome_text[0..visible_len], screen_row, padding);
}

fn printAt(window: vaxis.Window, text: []const u8, row: usize, col: usize) void {
    _ = window.printSegment(
        .{ .text = text },
        .{
            .row_offset = @intCast(row),
            .col_offset = @intCast(col),
            .wrap = .none,
        },
    );
}
