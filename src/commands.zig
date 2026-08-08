const std = @import("std");
const testing = std.testing;

const vaxis = @import("vaxis");
const editor = @import("editor/editor.zig");
const state = @import("editor/state.zig");

const Command = enum {
    // NAVIGATION
    left,
    right,
    up,
    down,
    doc_start_gg,
    document_end,
    line_start,
    line_end,
    middle,
    page_down,
    page_up,

    // INSERTION
    insert_left,
    insert_right,
    insert_start,
    insert_end,
    new_line_down,
    new_line_up,
    carriage_return,

    // MANIPULATION
    join_next_line,

    // DELETION
    delete_left,
    delete_current,
    delete_line,
    delete_line_remaining,

    // MODES
    normal,
    command,
    run_command,
    visual,
    replace,

    other,
};

pub fn handleKey(
    key: vaxis.Key,
    document: *editor.Editor,
    editor_state: *state.State,
    allocator: std.mem.Allocator,
) !bool {
    // load pending editor_state into a const so we don't have to false it every branch
    const pending_g = editor_state.pending_g;
    editor_state.pending_g = false;
    const pending_d = editor_state.pending_d;
    editor_state.pending_d = false;

    const command = commandFromKey(key, document, pending_g);

    switch (command) {
        // NAVIGATION
        .left => {
            if (document.cursor_x > 0) document.cursor_x -= 1;
        },
        .right => {
            if (document.currentRow()) |row| {
                if (document.cursor_x + 1 < row.chars.items.len) document.cursor_x += 1;
            }
        },
        .up => {
            if (document.cursor_y > 0) document.cursor_y -= 1;
        },
        .down => {
            if (document.cursor_y + 1 < document.rows.items.len) document.cursor_y += 1;
        },
        .doc_start_gg => {
            if (pending_g) {
                document.cursor_y = 0;
                editor_state.pending_g = false;
            } else {
                editor_state.pending_g = true;
            }
        },
        .document_end => {
            if (document.rows.items.len > 0) document.cursor_y = document.rows.items.len - 1;
        },
        .line_start => {
            document.cursor_x = 0;
            editor_state.pending_g = false;
        },
        .line_end => {
            if (document.currentRow()) |row| {
                document.cursor_x = if (row.chars.items.len == 0) 0 else row.chars.items.len - 1;
            } else {
                document.cursor_x = 0;
            }
            editor_state.pending_g = false;
        },
        .middle => {
            document.cursor_y = document.row_offset + document.rows_shown / 2 - 1;
        },
        .page_down => {
            document.cursor_y = document.cursor_y +| document.rows_shown / 2;
        },
        .page_up => {
            document.cursor_y = document.cursor_y -| document.rows_shown / 2;
        },

        // MODES
        .normal => {
            editor_state.clearText(document);
            document.mode = .NORMAL;
        },
        .insert_left => {
            document.mode = .INSERT;
        },
        .insert_right => {
            document.mode = .INSERT;
            document.cursor_x = document.cursor_x +| 1;
        },
        .insert_start => {
            document.mode = .INSERT;
            document.cursor_x = 0;
        },
        .insert_end => {
            document.mode = .INSERT;
            document.cursor_x = document.currentRow().?.chars.items.len;
        },
        .carriage_return => {
            try document.insertNewLine(allocator);
        },
        .new_line_up => {
            try document.insertRow(allocator, "", document.cursor_y);
            document.cursor_x = 0;
            document.mode = .INSERT;
        },
        .new_line_down => {
            if (document.rows.items.len == 0) {
                try document.insertRow(allocator, "", document.cursor_y);
            }
            try document.insertRow(allocator, "", document.cursor_y + 1);
            document.cursor_y += 1;
            document.cursor_x = 0;
            document.mode = .INSERT;
        },
        .join_next_line => {
            try document.joinWithNextRow(allocator);
        },
        .delete_left => {
            if (document.mode == .COMMAND) {
                if (editor_state.command_cursor_x > 1) {
                    editor_state.removeByte(editor_state.command_cursor_x - 1);
                    editor_state.command_cursor_x -= 1;
                }
            } else if (document.cursor_x != 0) {
                if (document.currentRow()) |row| {
                    row.removeByte(document.cursor_x - 1);
                    document.cursor_x -= 1;
                }
            } else {
                if (document.mode == .INSERT) {
                    try document.joinWithPrevRow(allocator);
                }
            }
        },
        .delete_current => {
            if (document.currentRow()) |row| {
                if (document.cursor_x < row.chars.items.len) {
                    row.removeByte(document.cursor_x);
                }
            }
        },
        .delete_line => {
            if (pending_d) {
                try document.removeRow(allocator, document.cursor_y);
                if (document.rows.items.len == 0) {
                    document.cursor_y = 0;
                } else if (document.cursor_y >= document.rows.items.len) {
                    document.cursor_y = document.cursor_y -| 1;
                }
                editor_state.pending_d = false;
            } else {
                editor_state.pending_d = true;
            }
        },
        .delete_line_remaining => {
            document.deleteRemainingLine();
        },
        .visual => document.mode = .VISUAL,
        .command => {
            document.mode = .COMMAND;
            // only append the ":" to the command line here
            // the rest of the text is appended in .other
            try editor_state.insertText(allocator, editor_state.command_cursor_x, ":");
            editor_state.command_cursor_x += 1;
        },
        .replace => document.mode = .REPLACE,
        .run_command => {
            if (std.mem.eql(u8, editor_state.command_buffer.items, ":w")) {
                editor_state.save_requested = true;
                editor_state.clearText(document);
            } else if (std.mem.eql(u8, editor_state.command_buffer.items, ":q")) {
                return true;
            } else if (std.mem.eql(u8, editor_state.command_buffer.items, ":wq")) {
                editor_state.save_requested = true;
                return true;
            }
        },
        .other => {
            editor_state.pending_g = false;
            editor_state.pending_d = false;
            if (document.mode == .INSERT) {
                if (key.text) |text| {
                    try document.insertText(allocator, text);
                }
            } else if (document.mode == .COMMAND) {
                if (key.text) |text| {
                    try editor_state.insertText(allocator, editor_state.command_cursor_x, text);
                    editor_state.command_cursor_x += text.len;
                }
            }
        },
    }

    clampCursorX(document);
    return false;
}

fn commandFromKey(key: vaxis.Key, document: *editor.Editor, pending_g: bool) Command {
    if (key.matches(vaxis.Key.escape, .{}) and document.mode != .NORMAL) return .normal;

    // NAVIGATION
    if (key.matches('G', .{}) and document.mode == .NORMAL) return .document_end;
    if (key.matches('0', .{}) and document.mode == .NORMAL) return .line_start;
    if (key.matches('h', .{}) and document.mode == .NORMAL and pending_g) return .line_start;
    if (key.matches('$', .{}) and document.mode == .NORMAL) return .line_end;
    if (key.matches('l', .{}) and document.mode == .NORMAL and pending_g) return .line_end;
    if (key.matches('g', .{}) and document.mode == .NORMAL) return .doc_start_gg;
    if (key.matches('M', .{}) and document.mode == .NORMAL) return .middle;
    if (key.matches('d', .{ .ctrl = true }) and document.mode == .NORMAL) return .page_down;
    if (key.matches('u', .{ .ctrl = true }) and document.mode == .NORMAL) return .page_up;
    if (key.matches(vaxis.Key.backspace, .{}) and document.mode == .NORMAL) return .left;
    if (key.matches(vaxis.Key.enter, .{}) and document.mode == .NORMAL) return .down;

    // these must come after otherwise pending g will never catch
    if (key.matches('h', .{}) and document.mode == .NORMAL) return .left;
    if (key.matches('j', .{}) and document.mode == .NORMAL) return .down;
    if (key.matches('k', .{}) and document.mode == .NORMAL) return .up;
    if (key.matches('l', .{}) and document.mode == .NORMAL) return .right;

    // INSERTION
    if (key.matches('i', .{}) and document.mode == .NORMAL) return .insert_left;
    if (key.matches('I', .{}) and document.mode == .NORMAL) return .insert_start;
    if (key.matches('a', .{}) and document.mode == .NORMAL) return .insert_right;
    if (key.matches('A', .{}) and document.mode == .NORMAL) return .insert_end;
    if (key.matches('o', .{}) and document.mode == .NORMAL) return .new_line_down;
    if (key.matches('O', .{}) and document.mode == .NORMAL) return .new_line_up;
    if (key.matches(vaxis.Key.enter, .{}) and document.mode == .INSERT) return .carriage_return;

    // MANIPULATION
    if (key.matches('J', .{}) and document.mode == .NORMAL) return .join_next_line;

    // DELETION
    if (key.matches(vaxis.Key.backspace, .{}) and document.mode == .INSERT) return .delete_left;
    if (key.matches(vaxis.Key.backspace, .{}) and document.mode == .COMMAND) return .delete_left;
    if (key.matches('x', .{}) and document.mode == .NORMAL) return .delete_current;
    if (key.matches('X', .{}) and document.mode == .NORMAL) return .delete_left;
    if (key.matches('d', .{}) and document.mode == .NORMAL) return .delete_line;
    if (key.matches('D', .{}) and document.mode == .NORMAL) return .delete_line_remaining;

    // MODES
    if (key.matches('r', .{}) and document.mode == .NORMAL) return .replace;
    if (key.matches('R', .{}) and document.mode == .NORMAL) return .replace;
    if (key.matches('v', .{}) and document.mode == .NORMAL) return .visual;
    if (key.matches('V', .{}) and document.mode == .NORMAL) return .visual;
    if (key.matches(':', .{}) and document.mode == .NORMAL) return .command;
    if (key.matches(vaxis.Key.enter, .{}) and document.mode == .COMMAND) return .run_command;

    // ARROWS
    return switch (key.codepoint) {
        vaxis.Key.left => .left,
        vaxis.Key.right => .right,
        vaxis.Key.up => .up,
        vaxis.Key.down => .down,
        else => .other,
    };
}

fn clampCursorX(document: *editor.Editor) void {
    const row = document.currentRow() orelse {
        document.cursor_x = 0;
        return;
    };

    if (row.chars.items.len == 0) {
        document.cursor_x = 0;
    } else if (document.cursor_x >= row.chars.items.len) {
        if (document.mode == .NORMAL) {
            document.cursor_x = row.chars.items.len - 1;
        } else {
            document.cursor_x = row.chars.items.len;
        }
    }
}

test "cursor clamps at final char in row when changing lines" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "this is a long line");
    try document.appendRow(allocator, "short");

    document.cursor_x = 18;
    _ = try handleKey(.{ .codepoint = 'j' }, &document, &editor_state, allocator);
    try testing.expect(document.cursor_x == 4);
}

test "gg and G move to document boundaries" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "second");
    try document.appendRow(allocator, "third");

    try testing.expect(!(try handleKey(.{ .codepoint = 'G' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 2), document.cursor_y);

    try testing.expect(!(try handleKey(.{ .codepoint = 'g' }, &document, &editor_state, allocator)));
    try testing.expect(editor_state.pending_g);
    try testing.expect(!(try handleKey(.{ .codepoint = 'g' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_y);
    try testing.expect(!editor_state.pending_g);
}

test "0 and gh move to line start" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "first");

    document.cursor_x = 3;
    try testing.expect(!(try handleKey(.{ .codepoint = '0' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_x);

    document.cursor_x = 3;
    try testing.expect(!(try handleKey(.{ .codepoint = 'g' }, &document, &editor_state, allocator)));
    try testing.expect(editor_state.pending_g);
    try testing.expect(!(try handleKey(.{ .codepoint = 'h' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_x);
}

test "$ and gl move to line end" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "first");

    try testing.expect(!(try handleKey(.{ .codepoint = '$' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 4), document.cursor_x);

    document.cursor_x = 0;
    try testing.expect(!(try handleKey(.{ .codepoint = 'g' }, &document, &editor_state, allocator)));
    try testing.expect(editor_state.pending_g);
    try testing.expect(!(try handleKey(.{ .codepoint = 'l' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 4), document.cursor_x);
}

test "hjkl work for movement in.NORMAL mode" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "second");
    try document.appendRow(allocator, "third");

    try testing.expect(document.mode == .NORMAL);
    try testing.expect(!(try handleKey(.{ .codepoint = 'l' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 1), document.cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = 'h' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = 'j' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 1), document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = 'k' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_y);

    document.mode = .INSERT;
    try testing.expect(!(try handleKey(.{ .codepoint = 'l' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = 'h' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = 'j' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = 'k' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_y);
}

test "arrows work for movement in all modes" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "second");
    try document.appendRow(allocator, "third");

    try testing.expect(document.mode == .NORMAL);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.right }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 1), document.cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.left }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.down }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 1), document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.up }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_y);

    document.mode = .INSERT;
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.right }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 1), document.cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.left }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.down }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 1), document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.up }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_y);

    document.mode = .VISUAL;
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.right }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 1), document.cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.left }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.down }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 1), document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.up }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_y);

    document.mode = .REPLACE;
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.right }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 1), document.cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.left }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.down }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 1), document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.up }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_y);

    document.mode = .COMMAND;
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.right }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 1), document.cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.left }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.down }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 1), document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.up }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_y);
}

test "modes change" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "second");
    try document.appendRow(allocator, "third");

    try testing.expect(document.mode == .NORMAL);
    try testing.expect(!(try handleKey(.{ .codepoint = 'i' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .INSERT);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'a' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .INSERT);

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expect(!(try handleKey(.{ .codepoint = 'r' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .REPLACE);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expect(!(try handleKey(.{ .codepoint = 'R' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .REPLACE);

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expect(!(try handleKey(.{ .codepoint = 'v' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .VISUAL);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expect(!(try handleKey(.{ .codepoint = 'V' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .VISUAL);
}

test "insert commands position cursor" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "first");

    try testing.expect(document.mode == .NORMAL);
    try testing.expect(!(try handleKey(.{ .codepoint = 'i' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .INSERT);
    try testing.expect(document.cursor_x == 0);

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expect(!(try handleKey(.{ .codepoint = 'a' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .INSERT);
    try testing.expect(document.cursor_x == 1);

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expect(!(try handleKey(.{ .codepoint = 'I' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .INSERT);
    try testing.expect(document.cursor_x == 0);

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expect(!(try handleKey(.{ .codepoint = 'A' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .INSERT);
    try testing.expect(document.cursor_x == document.currentRow().?.chars.items.len);
}

test "inserting text with commands" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try testing.expect(!(try handleKey(.{ .codepoint = 'i' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .INSERT);
    try testing.expect(document.cursor_x == 0);
    try testing.expect(!(try handleKey(.{ .codepoint = 'b', .text = "b" }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_x == 1);
    try testing.expect(!(try handleKey(.{ .codepoint = 'a', .text = "a" }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_x == 2);
    try testing.expectEqualStrings("ba", document.rows.items[document.cursor_y].chars.items);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expect(!(try handleKey(.{ .codepoint = '0' }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_x == 0);
    try testing.expect(!(try handleKey(.{ .codepoint = 'A' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .INSERT);
    try testing.expect(document.cursor_x == 2);
    try testing.expect(!(try handleKey(.{ .codepoint = 'n', .text = "n" }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("ban", document.rows.items[document.cursor_y].chars.items);
    try testing.expect(document.cursor_x == 3);
}

test "empty text on other keypress" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try testing.expect(!(try handleKey(.{ .codepoint = 'i' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .INSERT);
    try testing.expect(document.cursor_x == 0);
    try testing.expect(!(try handleKey(.{ .codepoint = 'b' }, &document, &editor_state, allocator)));
    try testing.expect(document.rows.items.len == 0);
}

test "backspace moves left in normal mode" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "first");
    document.cursor_x = 2;

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.backspace }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_x == 1);
}

test "backspace deletes char in insert mode" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    document.mode = .INSERT;
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.backspace }, &document, &editor_state, allocator)));
    try testing.expect(document.rows.items.len == 0);
    try testing.expect(document.cursor_x == 0);

    try document.appendRow(allocator, "first");
    document.cursor_x = 2;
    document.mode = .INSERT;

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.backspace }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("frst", document.rows.items[0].chars.items);
    try testing.expect(document.cursor_x == 1);
}

test "inserting new line with enter" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");

    try testing.expect(!(try handleKey(.{ .codepoint = 'A' }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_x == 0);
    try testing.expect(document.cursor_y == 1);
    try testing.expect(document.rows.items.len == 2);
    try testing.expectEqualStrings("hello", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("", document.rows.items[1].chars.items);
}

test "inserting new line with enter within word" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    document.cursor_x = 2;

    try testing.expect(!(try handleKey(.{ .codepoint = 'a' }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_x == 0);
    try testing.expect(document.cursor_y == 1);
    try testing.expect(document.rows.items.len == 2);
    try testing.expectEqualStrings("hel", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("lo", document.rows.items[1].chars.items);
}

test "inserting new line on empty file enter" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    document.mode = .INSERT;
    try testing.expect(document.rows.items.len == 0);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_x == 0);
    try testing.expect(document.cursor_y == 1);
    try testing.expect(document.rows.items.len == 2);
    try testing.expectEqualStrings("", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("", document.rows.items[1].chars.items);
}

test "inserting new line below with o" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "world");
    document.cursor_y = 0;

    try testing.expect(!(try handleKey(.{ .codepoint = 'o' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .INSERT);
    try testing.expect(document.cursor_x == 0);
    try testing.expect(document.cursor_y == 1);
    try testing.expect(document.rows.items.len == 3);
    try testing.expectEqualStrings("hello", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("", document.rows.items[1].chars.items);
    try testing.expectEqualStrings("world", document.rows.items[2].chars.items);
}

test "inserting new line on empty file o" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try testing.expect(document.rows.items.len == 0);
    try testing.expect(!(try handleKey(.{ .codepoint = 'o' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .INSERT);
    try testing.expect(document.cursor_x == 0);
    try testing.expect(document.cursor_y == 1);
    try testing.expect(document.rows.items.len == 2);
    try testing.expectEqualStrings("", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("", document.rows.items[1].chars.items);
}

test "inserting new line above with O" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "world");
    document.cursor_y = 0;

    try testing.expect(!(try handleKey(.{ .codepoint = 'O' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .INSERT);
    try testing.expect(document.cursor_x == 0);
    try testing.expect(document.cursor_y == 0);
    try testing.expect(document.rows.items.len == 3);
    try testing.expectEqualStrings("", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("hello", document.rows.items[1].chars.items);
    try testing.expectEqualStrings("world", document.rows.items[2].chars.items);
}

test "inserting new line on empty file O" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try testing.expect(document.rows.items.len == 0);
    try testing.expect(!(try handleKey(.{ .codepoint = 'O' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .INSERT);
    try testing.expect(document.cursor_x == 0);
    try testing.expect(document.cursor_y == 0);
    try testing.expect(document.rows.items.len == 1);
    try testing.expectEqualStrings("", document.rows.items[0].chars.items);
}

test "removing line with dd" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "world");
    document.cursor_y = 1;

    try testing.expect(document.rows.items.len == 2);
    try testing.expect(!(try handleKey(.{ .codepoint = 'd' }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'd' }, &document, &editor_state, allocator)));
    try testing.expect(document.rows.items.len == 1);
    try testing.expect(document.cursor_y == 0);
    try testing.expectEqualStrings("hello", document.rows.items[0].chars.items);

    try document.appendRow(allocator, "world");
    try document.appendRow(allocator, "world");
    try testing.expectEqualStrings("hello", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("world", document.rows.items[1].chars.items);
    try testing.expectEqualStrings("world", document.rows.items[2].chars.items);
    document.cursor_y = 1;
    try testing.expect(!(try handleKey(.{ .codepoint = 'd' }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'd' }, &document, &editor_state, allocator)));
    try testing.expect(document.rows.items.len == 2);
    try testing.expect(document.cursor_y == 1);
}

test "deleting line with dd does nothing on empty line" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try testing.expect(!(try handleKey(.{ .codepoint = 'd' }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'd' }, &document, &editor_state, allocator)));
    try testing.expect(document.rows.items.len == 0);
}

test "removing remainder of line with D" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    document.cursor_x = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = 'D' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("h", document.rows.items[0].chars.items);
}

test "removing remainder of line with D does nothing in empty line" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try testing.expect(!(try handleKey(.{ .codepoint = 'D' }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_y == 0);
    try testing.expect(document.cursor_x == 0);
    try testing.expect(document.rows.items.len == 0);
}

test "joining row with prev row" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, " world");
    document.cursor_y = 1;
    document.cursor_x = 0;
    document.mode = .INSERT;

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.backspace }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_y == 0);
    try testing.expect(document.rows.items.len == 1);
    try testing.expectEqualStrings("hello world", document.rows.items[0].chars.items);
}

test "joining row with prev row does nothing at top of file" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    document.cursor_y = 0;
    document.cursor_x = 0;
    document.mode = .INSERT;

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.backspace }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_y == 0);
    try testing.expect(document.rows.items.len == 1);
    try testing.expectEqualStrings("hello", document.rows.items[0].chars.items);
}

test "join row with next row" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, " world");
    try document.appendRow(allocator, " world");
    document.cursor_y = 0;
    document.cursor_x = 0;

    try testing.expect(!(try handleKey(.{ .codepoint = 'J' }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_y == 0);
    try testing.expect(document.rows.items.len == 2);
    try testing.expectEqualStrings("hello world", document.rows.items[0].chars.items);
}

test "join row with next row does nothing at end of file" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, " world");

    document.cursor_y = 1;
    try testing.expect(!(try handleKey(.{ .codepoint = 'J' }, &document, &editor_state, allocator)));
    try testing.expect(document.rows.items.len == 2);
    try testing.expectEqualStrings(" world", document.rows.items[1].chars.items);
}

test "x deletes char in normal mode" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "first");
    document.cursor_x = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = 'x' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("frst", document.rows.items[0].chars.items);
    try testing.expect(document.cursor_x == 1);
}

test "x does nothing in empty file / line" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try testing.expect(!(try handleKey(.{ .codepoint = 'x' }, &document, &editor_state, allocator)));
    try testing.expect(document.rows.items.len == 0);
    try testing.expect(document.cursor_x == 0);
}

test "X does nothing in empty file / line" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try testing.expect(!(try handleKey(.{ .codepoint = 'X' }, &document, &editor_state, allocator)));
    try testing.expect(document.rows.items.len == 0);
    try testing.expect(document.cursor_x == 0);
}

test "X deletes prev char in normal mode" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "first");
    document.cursor_x = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = 'X' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("irst", document.rows.items[0].chars.items);
    try testing.expect(document.cursor_x == 0);
}

test "save changes editor_state" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "first");

    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expect(editor_state.save_requested == true);
}

test "saving file with text" {
    const allocator = testing.allocator;
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};
    defer editor_state.deinit(allocator);

    document.filename = try allocator.dupe(u8, "test.txt");
    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "world");

    try document.saveFile(allocator, io, tmp.dir);

    const saved = try tmp.dir.readFileAlloc(io, "test.txt", allocator, .limited(1024));
    defer allocator.free(saved);

    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("hello\nworld", saved);
    try testing.expect(editor_state.save_requested == true);
}

test "adding text in command line" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'q', .text = "q" }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings(":wq", editor_state.command_buffer.items);
    try testing.expect(editor_state.command_cursor_x == 3);

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
}

test "deleting text in command line" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'q', .text = "q" }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings(":wq", editor_state.command_buffer.items);

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.backspace }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings(":w", editor_state.command_buffer.items);

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
}

test ":q quits" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{ .codepoint = 'q', .text = "q" }, &document, &editor_state, allocator)));
    try testing.expect((try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
}

test ":wq saves and quits" {
    const allocator = testing.allocator;
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};
    defer editor_state.deinit(allocator);

    document.filename = try allocator.dupe(u8, "test.txt");
    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "world");

    try document.saveFile(allocator, io, tmp.dir);

    const saved = try tmp.dir.readFileAlloc(io, "test.txt", allocator, .limited(1024));
    defer allocator.free(saved);

    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'q', .text = "q" }, &document, &editor_state, allocator)));
    try testing.expect((try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("hello\nworld", saved);
    try testing.expect(editor_state.save_requested == true);
}
