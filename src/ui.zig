const std = @import("std");
const testing = std.testing;
const vaxis = @import("vaxis");
const editor = @import("editor/editor.zig");
const state = @import("editor/state.zig");

const welcome_text = "Zag Editor -- Version 0.1.0";

pub fn refresh(
    vx: *vaxis.Vaxis,
    tty: *std.Io.Writer,
    document: *const editor.Editor,
    editor_state: *const state.State,
) !void {
    const window = vx.window();
    window.clear();
    drawRows(window, document, editor_state);

    var status_buf: [256]u8 = undefined;
    var cursor_buf: [256]u8 = undefined;
    try drawStatusBar(window, document, status_buf[0..], cursor_buf[0..]);

    var command_buf: [256]u8 = undefined;
    try drawCommandBar(window, editor_state, command_buf[0..]);

    var screen_x: usize = 0;
    var screen_y: usize = 0;
    if (document.mode == .COMMAND) {
        screen_x = editor_state.command_cursor_x;
        screen_y = window.height -| 1;
    } else {
        screen_x = document.render_x - document.col_offset;
        screen_y = document.cursor_y - document.row_offset;
    }
    window.showCursor(@intCast(screen_x), @intCast(screen_y));

    try vx.render(tty);
}

// TODO: add a ui testing library like cargo insta
fn drawRows(window: vaxis.Window, document: *const editor.Editor, editor_state: *const state.State) void {
    const query: ?[]const u8 = if (document.mode == .SEARCH and editor_state.command_buffer.items.len > 1)
        editor_state.command_buffer.items[1..]
    else if (document.mode == .NORMAL and editor_state.last_search.items.len > 0)
        editor_state.last_search.items
    else
        null;

    const text_height = window.height -| 2;
    for (0..text_height) |screen_row| {
        const file_row = document.row_offset + screen_row;

        if (file_row < document.rows.items.len) {
            const row = &document.rows.items[file_row];
            const chars = row.render.items;
            const start = @min(document.col_offset, chars.len);
            printAt(window, chars[start..], screen_row, 0);
            if (file_row == document.cursor_y and
                query != null and
                document.cursor_x <= row.chars.items.len and
                std.mem.startsWith(u8, row.chars.items[document.cursor_x..], query.?))
            {
                const active_query = query.?;
                const match_start_rx = row.cursorXtoRenderX(document.cursor_x);
                const match_end_cx = @min(document.cursor_x + active_query.len, row.chars.items.len);
                const match_end_rx = row.cursorXtoRenderX(match_end_cx);
                const visible_start = @max(match_start_rx, document.col_offset);
                const visible_end = @min(match_end_rx, document.col_offset + window.width);

                if (visible_start < visible_end) {
                    _ = window.printSegment(.{
                        .text = row.render.items[visible_start..visible_end],
                        .style = .{ .reverse = true },
                    }, .{
                        .row_offset = @intCast(screen_row),
                        .col_offset = @intCast(visible_start - document.col_offset),
                        .wrap = .none,
                    });
                }
            }
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

    const status_window = window.child(.{
        .y_off = @intCast(window.height -| 2),
        .height = 1,
    });
    status_window.fill(.{ .style = .{ .reverse = true } });

    // Show filename and lines in file
    const file: []const u8 = if (document.filename) |name| name else "[No File]";
    const edits_icon = unsavedEditsIcon(document);
    const file_text = try std.fmt.bufPrint(file_buf, " {s} | {s}{s} - {d} lines | {s}", .{ @tagName(document.mode), file, edits_icon, document.rows.items.len, @tagName(document.getFileType()) });
    _ = status_window.printSegment(.{
        .text = file_text,
        .style = .{ .reverse = true },
    }, .{ .wrap = .none });

    // Show cursor position
    const cursor_text = try std.fmt.bufPrint(cursor_buf, "{d}:{d}", .{ document.cursor_y + 1, document.cursor_x + 1 });
    const text_width: u16 = @intCast(cursor_text.len);
    const text_col = status_window.width -| text_width;
    _ = status_window.printSegment(.{
        .text = cursor_text,
        .style = .{ .reverse = true },
    }, .{
        .wrap = .none,
        .col_offset = text_col,
    });
}

fn unsavedEditsIcon(document: *const editor.Editor) []const u8 {
    return switch (document.unsaved_edits) {
        true => " [+]",
        else => "",
    };
}

fn drawCommandBar(
    window: vaxis.Window,
    editor_state: *const state.State,
    buf: []u8,
) !void {
    if (window.height == 0) {
        return;
    }

    const status_window = window.child(.{
        .y_off = @intCast(window.height -| 1),
        .height = 1,
    });

    const file_text = try std.fmt.bufPrint(buf, "{s}", .{editor_state.command_buffer.items});
    _ = status_window.printSegment(.{ .text = file_text }, .{ .wrap = .none });
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

// -------------------------------------------------------
// -------------------------------------------------------
// TESTS
// -------------------------------------------------------
// -------------------------------------------------------

test "unsaved edits icon" {
    var document = editor.Editor{};
    const allocator = testing.allocator;
    defer document.deinit(allocator);

    document.unsaved_edits = true;
    try testing.expectEqualStrings(" [+]", unsavedEditsIcon(&document));

    document.unsaved_edits = false;
    try testing.expectEqualStrings("", unsavedEditsIcon(&document));
}
