const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const vaxis = @import("vaxis");

const editor = @import("../editor/editor.zig");
const state = @import("../editor/state.zig");
const runner = @import("runner.zig");
const parser = @import("parser.zig");

pub const Command = enum {
    // NAVIGATION
    left,
    right,
    up,
    down,
    doc_start_gg,
    document_end,
    first_char,
    line_start,
    line_end,
    top,
    middle,
    bottom,
    page_down,
    page_up,
    next_word_start,
    next_word_end,
    last_word_start,
    next_space_start,
    next_space_end,
    last_space_start,
    next_empty_row,
    prev_empty_row,

    // INSERTION
    insert_left,
    insert_right,
    insert_start,
    insert_end,
    new_line_down,
    new_line_up,
    carriage_return,
    tab,

    // MANIPULATION
    join_next_line,
    substitute_char,
    substitute_line,

    // DELETION
    delete_left,
    delete_current,
    delete_line,
    delete_line_remaining,

    // MODES
    normal,
    command,
    run_command,
    search,
    search_next,
    search_prev,
    run_search,
    visual,
    replace,
    replace_mult,

    // Text insertion
    other,
};

pub fn handleKey(
    key: vaxis.Key,
    document: *editor.Editor,
    editor_state: *state.State,
    allocator: mem.Allocator,
) !bool {
    if (document.mode == .NORMAL) {
        if (key.text) |text| {
            editor_state.appendKeyToBuffer(text[0]);
        } else if (key.codepoint >= ' ' and key.codepoint <= '~') {
            // remove all special chars so its only u8
            editor_state.appendKeyToBuffer(@intCast(key.codepoint));
        }
    }

    const command = parser.keyActionParser(key, document, editor_state);
    const motion_count = switch (command) {
        .left, .right, .up, .down, .next_word_start, .delete_current, .delete_line => editor_state.pending_motion_count,
        else => 1,
    };

    var repeat_amount: usize = 0;
    while (repeat_amount < motion_count) : (repeat_amount += 1) {
        switch (command) {
            // NAVIGATION
            .left => {
                if (document.mode == .COMMAND or document.mode == .SEARCH) {
                    if (editor_state.command_cursor_x > 1) editor_state.command_cursor_x -= 1;
                } else {
                    if (document.cursor_x > 0) document.cursor_x -= 1;
                }
            },
            .right => {
                if (document.mode == .COMMAND or document.mode == .SEARCH) {
                    if (editor_state.command_cursor_x < editor_state.command_buffer.items.len) {
                        editor_state.command_cursor_x += 1;
                    }
                } else {
                    if (document.currentRow()) |row| {
                        if (document.cursor_x + 1 < row.chars.items.len) document.cursor_x += 1;
                    }
                }
            },
            .up => {
                if (document.cursor_y > 0) document.cursor_y -= 1;
            },
            .down => {
                if (document.cursor_y + 1 < document.rows.items.len) document.cursor_y += 1;
            },
            .doc_start_gg => {
                document.cursor_y = 0;
            },
            .document_end => {
                if (document.rows.items.len > 0) document.cursor_y = document.rows.items.len - 1;
            },
            .first_char => {
                if (std.mem.indexOfNone(u8, document.rows.items[document.cursor_y].render.items, " \t\r\n")) |pos| {
                    document.cursor_x = pos;
                } else {
                    document.cursor_x = 0;
                }
            },
            .line_start => {
                document.cursor_x = 0;
            },
            .line_end => {
                if (document.currentRow()) |row| {
                    document.cursor_x = if (row.chars.items.len == 0) 0 else row.chars.items.len - 1;
                } else {
                    document.cursor_x = 0;
                }
            },
            .top => {
                document.cursor_y = document.row_offset;
            },
            .middle => {
                document.cursor_y = document.row_offset + document.rows_shown / 2;
            },
            .bottom => {
                document.cursor_y = document.row_offset + document.rows_shown - 1;
            },
            .page_down => {
                if (document.cursor_y + document.rows_shown / 2 > document.rows.items.len) {
                    document.cursor_y = document.rows.items.len - 1;
                } else {
                    document.cursor_y = document.cursor_y +| document.rows_shown / 2;
                }
            },
            .page_up => {
                document.cursor_y = document.cursor_y -| document.rows_shown / 2;
            },
            .next_word_start => {
                document.moveForward(.partial, .start);
            },
            .next_word_end => {
                document.moveForward(.partial, .end);
            },
            .last_word_start => {
                document.moveBack(.partial);
            },
            .next_space_start => {
                document.moveForward(.full, .start);
            },
            .next_space_end => {
                document.moveForward(.full, .end);
            },
            .last_space_start => {
                document.moveBack(.full);
            },
            .next_empty_row => {
                document.jumpByParagraph(.forward);
            },
            .prev_empty_row => {
                document.jumpByParagraph(.backward);
            },

            // MODES
            .normal => {
                if (document.mode == .SEARCH) {
                    document.cursor_x = editor_state.cursor_origin_x;
                    document.cursor_y = editor_state.cursor_origin_y;
                }
                editor_state.clearText(document);
                editor_state.replace_mult = false;
                editor_state.pending_motion_len = 0;
            },
            .visual => document.mode = .VISUAL,
            .command => {
                editor_state.clearText(document);
                document.mode = .COMMAND;
                // only append the ":" to the command line here
                // the rest of the text is appended in .other
                try editor_state.insertText(allocator, editor_state.command_cursor_x, ":");
                editor_state.command_cursor_x += 1;
            },
            .search => {
                editor_state.cursor_origin_x = document.cursor_x;
                editor_state.cursor_origin_y = document.cursor_y;
                editor_state.clearText(document);
                document.mode = .SEARCH;
                try editor_state.insertText(allocator, editor_state.command_cursor_x, "/");
                editor_state.command_cursor_x += 1;
            },
            .search_next => {
                if (editor_state.last_search.items.len != 0) {
                    const found = document.search(editor_state.last_search.items, document.cursor_y, document.cursor_x + 1, .forward);
                    editor_state.invalid_search = !found;
                }
            },
            .search_prev => {
                if (editor_state.last_search.items.len != 0) {
                    const found = document.search(editor_state.last_search.items, document.cursor_y, document.cursor_x, .backward);
                    editor_state.invalid_search = !found;
                }
            },
            .replace => {
                document.mode = .REPLACE;
            },
            .replace_mult => {
                document.mode = .REPLACE;
                editor_state.replace_mult = true;
            },
            .run_search => {
                const found = document.search(editor_state.command_buffer.items[1..], editor_state.cursor_origin_y, editor_state.cursor_origin_x, .forward);
                try editor_state.setLastSearch(allocator);
                editor_state.clearText(document);
                editor_state.invalid_search = !found;
            },
            .run_command => {
                if (try runner.runCommand(editor_state, document, allocator)) return true;
            },

            // INSERTING TEXT
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
            .tab => {
                if (document.rows.items.len == 0) {
                    try document.insertRow(allocator, "", 0);
                }

                if (document.currentRow()) |row| {
                    const tab_width = 4 - (document.cursor_x % 4);
                    const spaces = try row.chars.addManyAt(allocator, document.cursor_x, tab_width);
                    @memset(spaces, ' ');
                    document.cursor_x += tab_width;
                    try document.rows.items[document.cursor_y].updateRender(allocator);
                }
            },
            .new_line_up => {
                try document.insertRow(allocator, "", document.cursor_y);

                if (document.rows.items.len != 0 and document.cursor_y != 0) {
                    const first_char = mem.indexOfNone(u8, document.rows.items[document.cursor_y - 1].chars.items, " \t") orelse document.rows.items[document.cursor_y - 1].chars.items.len;
                    try document.rows.items[document.cursor_y].insertText(allocator, 0, document.rows.items[document.cursor_y - 1].chars.items[0..first_char]);

                    if (mem.endsWith(u8, document.rows.items[document.cursor_y - 1].chars.items, "{")) {
                        try document.rows.items[document.cursor_y].insertText(allocator, first_char, "\t");
                        document.cursor_x = first_char + 1;
                    } else {
                        document.cursor_x = first_char;
                    }
                }

                document.mode = .INSERT;
            },
            .new_line_down => {
                if (document.rows.items.len == 0) {
                    try document.insertRow(allocator, "", document.cursor_y);
                }
                try document.insertRow(allocator, "", document.cursor_y + 1);

                const first_char = mem.indexOfNone(u8, document.rows.items[document.cursor_y].chars.items, " \t") orelse document.rows.items[document.cursor_y].chars.items.len;

                try document.rows.items[document.cursor_y + 1].insertText(allocator, 0, document.rows.items[document.cursor_y].chars.items[0..first_char]);
                if (mem.endsWith(u8, document.rows.items[document.cursor_y].chars.items, "{")) {
                    try document.rows.items[document.cursor_y + 1].insertText(allocator, first_char, "\t");
                    document.cursor_x = first_char + 1;
                } else {
                    document.cursor_x = first_char;
                }

                document.cursor_y += 1;
                document.mode = .INSERT;
            },

            // MANIPULATING TEXT
            .join_next_line => {
                try document.joinWithNextRow(allocator);
            },
            .substitute_char => {
                document.mode = .INSERT;

                if (document.currentRow()) |row| {
                    if (document.cursor_x != 0) {
                        try row.removeByte(document.cursor_x - 1, allocator);
                        document.cursor_x -= 1;
                    } else {
                        if (row.chars.items.len != 0) {
                            try row.removeByte(document.cursor_x, allocator);
                        }
                    }
                }

                document.syntax_dirty = true;
            },
            .substitute_line => {
                if (document.currentRow()) |row| {
                    row.chars.clearRetainingCapacity();
                    try row.updateRender(allocator);
                    document.mode = .INSERT;
                } else {
                    document.mode = .INSERT;
                }
                document.syntax_dirty = true;
            },

            // DELETING TEXT
            .delete_left => {
                if (document.mode == .COMMAND) {
                    if (editor_state.command_cursor_x > 1) {
                        editor_state.removeByte(editor_state.command_cursor_x - 1);
                        editor_state.command_cursor_x -= 1;
                    }
                } else if (document.mode == .SEARCH) {
                    if (editor_state.command_cursor_x > 1) {
                        editor_state.removeByte(editor_state.command_cursor_x - 1);
                        editor_state.command_cursor_x -= 1;
                    }
                    _ = document.search(editor_state.command_buffer.items[1..], editor_state.cursor_origin_y, editor_state.cursor_origin_x, .forward);
                } else if (document.cursor_x != 0) {
                    if (document.currentRow()) |row| {
                        try row.removeByte(document.cursor_x - 1, allocator);
                        document.cursor_x -= 1;
                    }
                } else {
                    if (document.mode == .INSERT) {
                        try document.joinWithPrevRow(allocator);
                    }
                }
                document.syntax_dirty = true;
            },
            .delete_current => {
                if (document.currentRow()) |row| {
                    if (document.cursor_x < row.chars.items.len) {
                        try row.removeByte(document.cursor_x, allocator);
                    }
                }
                document.syntax_dirty = true;
            },
            .delete_line => {
                try document.removeRow(allocator, document.cursor_y);
                if (document.rows.items.len == 0) {
                    document.cursor_y = 0;
                } else if (document.cursor_y >= document.rows.items.len) {
                    document.cursor_y = document.cursor_y -| 1;
                }
            },
            .delete_line_remaining => {
                try document.deleteRemainingLine(allocator);
            },

            .other => {
                if (document.mode == .INSERT) {
                    if (key.text) |text| {
                        try document.insertText(allocator, text);
                    }
                } else if (document.mode == .COMMAND) {
                    if (key.text) |text| {
                        try editor_state.insertText(allocator, editor_state.command_cursor_x, text);
                        editor_state.command_cursor_x += text.len;
                    }
                } else if (document.mode == .REPLACE) {
                    if (key.text) |text| {
                        if (editor_state.replace_mult) {
                            try document.replaceChar(allocator, text, document.cursor_x);
                            document.cursor_x += 1;
                        } else {
                            try document.replaceChar(allocator, text, document.cursor_x);
                            document.mode = .NORMAL;
                        }
                    }
                } else if (document.mode == .SEARCH) {
                    if (key.text) |text| {
                        try editor_state.insertText(allocator, editor_state.command_cursor_x, text);
                        editor_state.command_cursor_x += text.len;
                        _ = document.search(editor_state.command_buffer.items[1..], editor_state.cursor_origin_y, editor_state.cursor_origin_x, .forward);
                    }
                }
            },
        }
    }

    if (command != .other) {
        editor_state.pending_motion_len = 0;
        editor_state.pending_motion_count = 1;
    }

    document.clampCursorX();
    return false;
}

// -------------------------------------------------------
// -------------------------------------------------------
// TESTS
// -------------------------------------------------------
// -------------------------------------------------------

// CHANGING MODES
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

// MOVEMENT
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'g' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 0), document.cursor_y);
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'l' }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 4), document.cursor_x);
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
    defer editor_state.deinit(allocator);

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
    try editor_state.insertText(allocator, editor_state.command_cursor_x, "wq");
    editor_state.command_cursor_x = 1;
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.left }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 1), editor_state.command_cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.right }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 2), editor_state.command_cursor_x);

    document.mode = .SEARCH;
    try editor_state.insertText(allocator, editor_state.command_cursor_x, "wq");
    editor_state.command_cursor_x = 1;
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.left }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 1), editor_state.command_cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.right }, &document, &editor_state, allocator)));
    try testing.expectEqual(@as(usize, 2), editor_state.command_cursor_x);
}
test "ctrl-u jumps half page up" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    document.rows_shown = 10;
    document.cursor_y = 10;
    try testing.expect(!(try handleKey(.{
        .codepoint = 'u',
        .mods = .{ .ctrl = true },
    }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_y == 5);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'u',
        .mods = .{ .ctrl = true },
    }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_y == 0);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'u',
        .mods = .{ .ctrl = true },
    }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_y == 0);
}

test "ctrl-d jumps half page down" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "hello");

    document.rows_shown = 10;
    try testing.expect(!(try handleKey(.{
        .codepoint = 'd',
        .mods = .{ .ctrl = true },
    }, &document, &editor_state, allocator)));
    try testing.expectEqual(5, document.cursor_y);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'd',
        .mods = .{ .ctrl = true },
    }, &document, &editor_state, allocator)));
    try testing.expectEqual(10, document.cursor_y);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'd',
        .mods = .{ .ctrl = true },
    }, &document, &editor_state, allocator)));
    try testing.expectEqual(10, document.cursor_y);
}

test "M jumps to midscreen" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "first");

    document.row_offset = 4;
    document.rows_shown = 10;

    try testing.expectEqual(0, document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = 'M' }, &document, &editor_state, allocator)));
    try testing.expectEqual(9, document.cursor_y);
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

test "move back to last word" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello world foo.bar");

    try testing.expect(!(try handleKey(.{ .codepoint = 'b' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);

    document.cursor_x = 4;
    try testing.expect(!(try handleKey(.{ .codepoint = 'b' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);

    document.cursor_x = 5;
    try testing.expect(!(try handleKey(.{ .codepoint = 'b' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);

    document.cursor_x = 8;
    try testing.expect(!(try handleKey(.{ .codepoint = 'b' }, &document, &editor_state, allocator)));
    try testing.expectEqual(6, document.cursor_x);

    document.cursor_x = 16;
    try testing.expect(!(try handleKey(.{ .codepoint = 'b' }, &document, &editor_state, allocator)));
    try testing.expectEqual(15, document.cursor_x);

    document.cursor_x = 15;
    try testing.expect(!(try handleKey(.{ .codepoint = 'b' }, &document, &editor_state, allocator)));
    try testing.expectEqual(12, document.cursor_x);
}

test "move back to last space" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello world foo.bar");

    try testing.expect(!(try handleKey(.{ .codepoint = 'B' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);

    document.cursor_x = 4;
    try testing.expect(!(try handleKey(.{ .codepoint = 'B' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);

    document.cursor_x = 5;
    try testing.expect(!(try handleKey(.{ .codepoint = 'B' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);

    document.cursor_x = 8;
    try testing.expect(!(try handleKey(.{ .codepoint = 'B' }, &document, &editor_state, allocator)));
    try testing.expectEqual(6, document.cursor_x);

    document.cursor_x = 16;
    try testing.expect(!(try handleKey(.{ .codepoint = 'B' }, &document, &editor_state, allocator)));
    try testing.expectEqual(12, document.cursor_x);

    document.cursor_x = 15;
    try testing.expect(!(try handleKey(.{ .codepoint = 'B' }, &document, &editor_state, allocator)));
    try testing.expectEqual(12, document.cursor_x);
}

test "move forward to next word end" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello world foo.bar");

    try testing.expect(!(try handleKey(.{ .codepoint = 'e' }, &document, &editor_state, allocator)));
    try testing.expectEqual(4, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'e' }, &document, &editor_state, allocator)));
    try testing.expectEqual(10, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'e' }, &document, &editor_state, allocator)));
    try testing.expectEqual(14, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'e' }, &document, &editor_state, allocator)));
    try testing.expectEqual(15, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'e' }, &document, &editor_state, allocator)));
    try testing.expectEqual(18, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'e' }, &document, &editor_state, allocator)));
    try testing.expectEqual(18, document.cursor_x);
}

test "move forward to next space end" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello world foo.bar");

    try testing.expect(!(try handleKey(.{ .codepoint = 'E' }, &document, &editor_state, allocator)));
    try testing.expectEqual(4, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'E' }, &document, &editor_state, allocator)));
    try testing.expectEqual(10, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'E' }, &document, &editor_state, allocator)));
    try testing.expectEqual(18, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'E' }, &document, &editor_state, allocator)));
    try testing.expectEqual(18, document.cursor_x);
}

test "move forward to next word start" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello world foo.bar");

    try testing.expect(!(try handleKey(.{ .codepoint = 'w' }, &document, &editor_state, allocator)));
    try testing.expectEqual(6, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'w' }, &document, &editor_state, allocator)));
    try testing.expectEqual(12, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'w' }, &document, &editor_state, allocator)));
    try testing.expectEqual(15, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'w' }, &document, &editor_state, allocator)));
    try testing.expectEqual(16, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'w' }, &document, &editor_state, allocator)));
    try testing.expectEqual(18, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'w' }, &document, &editor_state, allocator)));
    try testing.expectEqual(18, document.cursor_x);
}

test "move forward to next space start" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello foo.bar world");

    try testing.expect(!(try handleKey(.{ .codepoint = 'W' }, &document, &editor_state, allocator)));
    try testing.expectEqual(6, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'W' }, &document, &editor_state, allocator)));
    try testing.expectEqual(14, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'W' }, &document, &editor_state, allocator)));
    try testing.expectEqual(18, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'W' }, &document, &editor_state, allocator)));
    try testing.expectEqual(18, document.cursor_x);
}

test "word motions starting on blank chars" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "a  b");

    document.cursor_x = 1;
    try testing.expect(!(try handleKey(.{ .codepoint = 'w' }, &document, &editor_state, allocator)));
    try testing.expectEqual(3, document.cursor_x);

    document.cursor_x = 1;
    try testing.expect(!(try handleKey(.{ .codepoint = 'e' }, &document, &editor_state, allocator)));
    try testing.expectEqual(3, document.cursor_x);

    document.cursor_x = 1;
    try testing.expect(!(try handleKey(.{ .codepoint = 'W' }, &document, &editor_state, allocator)));
    try testing.expectEqual(3, document.cursor_x);

    document.cursor_x = 1;
    try testing.expect(!(try handleKey(.{ .codepoint = 'E' }, &document, &editor_state, allocator)));
    try testing.expectEqual(3, document.cursor_x);

    document.cursor_x = 3;
    try testing.expect(!(try handleKey(.{ .codepoint = 'b' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);

    document.cursor_x = 2;
    try testing.expect(!(try handleKey(.{ .codepoint = 'b' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);

    document.cursor_x = 1;
    try testing.expect(!(try handleKey(.{ .codepoint = 'b' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);
}

test "word motions treat tab as blank" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "a\tb");

    document.cursor_x = 1;
    try testing.expect(!(try handleKey(.{ .codepoint = 'w' }, &document, &editor_state, allocator)));
    try testing.expectEqual(2, document.cursor_x);

    document.cursor_x = 0;
    try testing.expect(!(try handleKey(.{ .codepoint = 'e' }, &document, &editor_state, allocator)));
    try testing.expectEqual(2, document.cursor_x);

    document.cursor_x = 2;
    try testing.expect(!(try handleKey(.{ .codepoint = 'b' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);
}

test "word motions on all blank row stay on line" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "   ");

    try testing.expect(!(try handleKey(.{ .codepoint = 'w' }, &document, &editor_state, allocator)));
    try testing.expectEqual(2, document.cursor_x);

    document.cursor_x = 0;
    try testing.expect(!(try handleKey(.{ .codepoint = 'e' }, &document, &editor_state, allocator)));
    try testing.expectEqual(2, document.cursor_x);

    document.cursor_x = 2;
    try testing.expect(!(try handleKey(.{ .codepoint = 'b' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);
}

test "word motions do nothing on empty row" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "");

    try testing.expect(!(try handleKey(.{ .codepoint = 'w' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'e' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'b' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);
}

test "word motions do nothing on empty file" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try testing.expect(!(try handleKey(.{ .codepoint = 'w' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);

    try testing.expect(!(try handleKey(.{ .codepoint = 'b' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_x);
}

test "jump to next paragraph (blank line)" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "");
    try document.appendRow(allocator, "world");
    try document.appendRow(allocator, "how's it going");
    try document.appendRow(allocator, "");

    try testing.expect(!(try handleKey(.{ .codepoint = '}' }, &document, &editor_state, allocator)));
    try testing.expectEqual(1, document.cursor_y);

    try testing.expect(!(try handleKey(.{ .codepoint = '}' }, &document, &editor_state, allocator)));
    try testing.expectEqual(4, document.cursor_y);

    try testing.expect(!(try handleKey(.{ .codepoint = '}' }, &document, &editor_state, allocator)));
    try testing.expectEqual(4, document.cursor_y);
}

test "jump to prev paragraph (blank line)" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "");
    try document.appendRow(allocator, "world");
    try document.appendRow(allocator, "how's it going");
    try document.appendRow(allocator, "");
    document.cursor_y = 4;

    try testing.expect(!(try handleKey(.{ .codepoint = '{' }, &document, &editor_state, allocator)));
    try testing.expectEqual(1, document.cursor_y);

    try testing.expect(!(try handleKey(.{ .codepoint = '{' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_y);

    try testing.expect(!(try handleKey(.{ .codepoint = '{' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_y);
}

test "jump to paragraph does nothing on empty row" {
    const allocator = testing.allocator;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "");

    try testing.expect(!(try handleKey(.{ .codepoint = '}' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_y);

    try testing.expect(!(try handleKey(.{ .codepoint = '{' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_y);
}

test "jump to paragraph does nothing on empty file" {
    const allocator = testing.allocator;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try testing.expect(!(try handleKey(.{ .codepoint = '}' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_y);

    try testing.expect(!(try handleKey(.{ .codepoint = '{' }, &document, &editor_state, allocator)));
    try testing.expectEqual(0, document.cursor_y);
}

// INSERTING TEXT
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
    try testing.expect(!(try handleKey(.{
        .codepoint = 'b',
        .text = "b",
    }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_x == 1);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'a',
        .text = "a",
    }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_x == 2);
    try testing.expectEqualStrings("ba", document.rows.items[document.cursor_y].chars.items);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expect(!(try handleKey(.{ .codepoint = '0' }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_x == 0);
    try testing.expect(!(try handleKey(.{ .codepoint = 'A' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .INSERT);
    try testing.expect(document.cursor_x == 2);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'n',
        .text = "n",
    }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("ban", document.rows.items[document.cursor_y].chars.items);
    try testing.expect(document.cursor_x == 3);
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

test "inserting new line above with \t" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "\tend");
    try document.appendRow(allocator, "}");
    document.cursor_y = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = 'O' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("\tend", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("\t", document.rows.items[1].chars.items);
    try testing.expectEqualStrings("}", document.rows.items[2].chars.items);
}

test "inserting new line above with spaces" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "    end");
    try document.appendRow(allocator, "}");
    document.cursor_y = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = 'O' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("    end", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("    ", document.rows.items[1].chars.items);
    try testing.expectEqualStrings("}", document.rows.items[2].chars.items);
}

test "inserting new line above with spaces and no text" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "    ");

    try testing.expect(!(try handleKey(.{ .codepoint = 'O' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("    ", document.rows.items[1].chars.items);
}

test "inserting new line above with \t and no text" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "\t");

    try testing.expect(!(try handleKey(.{ .codepoint = 'O' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("\t", document.rows.items[1].chars.items);
}

test "inserting new line with spaces and no text" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "    ");

    try testing.expect(!(try handleKey(.{ .codepoint = 'o' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("    ", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("    ", document.rows.items[1].chars.items);
}

test "inserting new line with \t and no text" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "\t");

    try testing.expect(!(try handleKey(.{ .codepoint = 'o' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("\t", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("\t", document.rows.items[1].chars.items);
}

test "inserting new row with \t in current line" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "zero");
    try document.appendRow(allocator, "\tone");
    document.cursor_y = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = 'o' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("zero", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("\tone", document.rows.items[1].chars.items);
    try testing.expectEqualStrings("\t", document.rows.items[2].chars.items);
}

test "inserting new row with multiple \t in current line" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "zero");
    try document.appendRow(allocator, "\t\tone");
    document.cursor_y = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = 'o' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("zero", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("\t\tone", document.rows.items[1].chars.items);
    try testing.expectEqualStrings("\t\t", document.rows.items[2].chars.items);
}

test "inserting new row with spaces instead of tabs in current line" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "zero");
    try document.appendRow(allocator, "    one");
    document.cursor_y = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = 'o' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("zero", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("    one", document.rows.items[1].chars.items);
    try testing.expectEqualStrings("    ", document.rows.items[2].chars.items);
}

test "inserting new row with multiple spaces instead of tabs in current line" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "zero");
    try document.appendRow(allocator, "        one");
    document.cursor_y = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = 'o' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("zero", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("        one", document.rows.items[1].chars.items);
    try testing.expectEqualStrings("        ", document.rows.items[2].chars.items);
}

test "inserting new row with { at end of line" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "zero");
    try document.appendRow(allocator, "one {");
    document.cursor_y = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = 'o' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("zero", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("one {", document.rows.items[1].chars.items);
    try testing.expectEqualStrings("\t", document.rows.items[2].chars.items);
}

test "inserting new row with { and \t" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "zero");
    try document.appendRow(allocator, "\tone {");
    document.cursor_y = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = 'o' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("zero", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("\tone {", document.rows.items[1].chars.items);
    try testing.expectEqualStrings("\t\t", document.rows.items[2].chars.items);
}

test "inserting new row with { and nested \t" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "zero");
    try document.appendRow(allocator, "\t\t\tone {");
    document.cursor_y = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = 'o' }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("zero", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("\t\t\tone {", document.rows.items[1].chars.items);
    try testing.expectEqualStrings("\t\t\t\t", document.rows.items[2].chars.items);
}

test "tab inserts 4 spaces on empty row" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "");
    document.mode = .INSERT;

    try testing.expectEqual(document.cursor_x, 0);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.tab }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("    ", document.rows.items[0].render.items);
}

test "tab inserts 4 spaces on no row" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    document.mode = .INSERT;

    try testing.expectEqual(document.cursor_x, 0);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.tab }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("    ", document.rows.items[0].render.items);
}

test "tab inserts 4 spaces at the end of the row" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    document.mode = .INSERT;
    try document.appendRow(allocator, "hello");
    document.cursor_x = document.rows.items[document.cursor_y].chars.items.len;

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.tab }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("hello   ", document.rows.items[0].render.items);
}

test "tab inserts spaces at the middle of the row" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    document.mode = .INSERT;
    try document.appendRow(allocator, "hello");
    document.cursor_x = 2;

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.tab }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("he  llo", document.rows.items[0].render.items);
}

// JOINING ROWS
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

// MANIPULATING TEXT
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

test "substituting char at cursor x 0" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, " world");
    try document.appendRow(allocator, " world");
    document.cursor_y = 0;
    document.cursor_x = 0;

    try testing.expect(!(try handleKey(.{ .codepoint = 's' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.INSERT, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("wello", document.rows.items[0].chars.items);
}

test "substituting char" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, " world");
    try document.appendRow(allocator, " world");
    document.cursor_y = 0;
    document.cursor_x = 2;

    try testing.expect(!(try handleKey(.{ .codepoint = 's' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.INSERT, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("hwwllo", document.rows.items[0].chars.items);
}

test "substituting char on empty file" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try testing.expect(!(try handleKey(.{ .codepoint = 's' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.INSERT, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("w", document.rows.items[0].chars.items);
}

test "substituting char on empty line" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "");

    try testing.expect(!(try handleKey(.{ .codepoint = 's' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.INSERT, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("w", document.rows.items[0].chars.items);
}

test "substituting line at cursor x 0" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, " world");
    try document.appendRow(allocator, " world");
    document.cursor_y = 0;
    document.cursor_x = 0;

    try testing.expect(!(try handleKey(.{ .codepoint = 'S' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.INSERT, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("w", document.rows.items[0].chars.items);
}

test "substituting line" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, " world");
    try document.appendRow(allocator, " world");
    document.cursor_y = 0;
    document.cursor_x = 2;

    try testing.expect(!(try handleKey(.{ .codepoint = 'S' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.INSERT, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("ww", document.rows.items[0].chars.items);
}

test "substituting line on empty file" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try testing.expect(!(try handleKey(.{ .codepoint = 'S' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.INSERT, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("w", document.rows.items[0].chars.items);
}

test "substituting line on empty line" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try document.appendRow(allocator, "");

    try testing.expect(!(try handleKey(.{ .codepoint = 'S' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.INSERT, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("w", document.rows.items[0].chars.items);
}

// DELETING TEXT
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

// SAVING FILES
test "save changes editor_state" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "first");

    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
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

    const result = try document.saveFile(allocator, io, tmp.dir);
    try testing.expectEqual(.success, result);

    const saved = try tmp.dir.readFileAlloc(io, "test.txt", allocator, .limited(1024));
    defer allocator.free(saved);

    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("hello\nworld", saved);
    try testing.expect(editor_state.save_requested);
}

// COMMAND MODE
test "typing : enters command mode" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.COMMAND, document.mode);
}

test "cursor can't move left of / or : in command bar" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try testing.expect(!(try handleKey(.{ .codepoint = '/' }, &document, &editor_state, allocator)));
    try testing.expectEqual(1, editor_state.command_cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.left }, &document, &editor_state, allocator)));
    try testing.expectEqual(1, editor_state.command_cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));

    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expectEqual(1, editor_state.command_cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.left }, &document, &editor_state, allocator)));
    try testing.expectEqual(1, editor_state.command_cursor_x);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
}

test "adding text in command line" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'q',
        .text = "q",
    }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'q',
        .text = "q",
    }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings(":wq", editor_state.command_buffer.items);

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.backspace }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings(":w", editor_state.command_buffer.items);

    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
}

test ":q quits with no unsaved edits" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try testing.expect(!editor_state.quit_blocked);
    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'q',
        .text = "q",
    }, &document, &editor_state, allocator)));
    try testing.expect((try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
}

test ":q fails with unsaved edits" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};
    defer editor_state.deinit(allocator);

    document.unsaved_edits = true;
    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'q',
        .text = "q",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expect(editor_state.quit_blocked);
}

test ":q! quits with no unsaved edits" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try testing.expect(!editor_state.quit_blocked);
    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'q',
        .text = "q",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = '!',
        .text = "!",
    }, &document, &editor_state, allocator)));
    try testing.expect((try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expect(!editor_state.quit_blocked);
}

test ":q! quits with unsaved edits" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};
    defer editor_state.deinit(allocator);

    document.unsaved_edits = true;
    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'q',
        .text = "q",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = '!',
        .text = "!",
    }, &document, &editor_state, allocator)));
    try testing.expect((try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expect(!editor_state.quit_blocked);
}

test ":w saves" {
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

    const result = try document.saveFile(allocator, io, tmp.dir);
    try testing.expectEqual(.success, result);

    const saved = try tmp.dir.readFileAlloc(io, "test.txt", allocator, .limited(1024));
    defer allocator.free(saved);

    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("hello\nworld", saved);
    try testing.expect(editor_state.save_requested == true);
}

test ":w {filename} saves with a filename" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "world");

    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = ' ',
        .text = " ",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'a',
        .text = "a",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("hello", document.rows.items[0].chars.items);
    try testing.expect(editor_state.save_requested == true);
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

    const result = try document.saveFile(allocator, io, tmp.dir);
    try testing.expectEqual(.success, result);

    const saved = try tmp.dir.readFileAlloc(io, "test.txt", allocator, .limited(1024));
    defer allocator.free(saved);

    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'q',
        .text = "q",
    }, &document, &editor_state, allocator)));
    try testing.expect((try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("hello\nworld", saved);
    try testing.expect(editor_state.save_requested == true);
}

// SEARCH MODE
test "typing / enters search mode" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try testing.expect(!(try handleKey(.{ .codepoint = '/' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.SEARCH, document.mode);
    try testing.expectEqualStrings("/", editor_state.command_buffer.items);
    try testing.expectEqual(1, editor_state.command_cursor_x);
}

test "enter copies buffer to last search" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try testing.expect(!(try handleKey(.{ .codepoint = '/' }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'o',
        .text = "o",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("o", editor_state.last_search.items);
}

test "escape from search returns cursor to last pos" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "world");
    document.cursor_x = 4;
    document.cursor_y = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = '/' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.SEARCH, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'l',
        .text = "l",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'o',
        .text = "o",
    }, &document, &editor_state, allocator)));
    try testing.expectEqual(3, document.cursor_x);
    try testing.expectEqual(0, document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expectEqual(.NORMAL, document.mode);
    try testing.expectEqual(4, document.cursor_x);
    try testing.expectEqual(1, document.cursor_y);
}

test "text handling in search mode" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try testing.expect(!(try handleKey(.{ .codepoint = '/' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.SEARCH, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'q',
        .text = "q",
    }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("/wq", editor_state.command_buffer.items);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.backspace }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("/w", editor_state.command_buffer.items);
    try testing.expectEqual(2, editor_state.command_cursor_x);
}

test "searching with /" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "quit zag with wq or q or q!");

    try testing.expect(!(try handleKey(.{ .codepoint = '/' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.SEARCH, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'q',
        .text = "q",
    }, &document, &editor_state, allocator)));
    try testing.expect(!editor_state.invalid_search);
    try testing.expectEqual(14, document.cursor_x);
    try testing.expectEqual(0, document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expectEqual(.NORMAL, document.mode);
    try testing.expect(!editor_state.invalid_search);
    try testing.expectEqual(14, document.cursor_x);
    try testing.expectEqual(0, document.cursor_y);

    try testing.expect(!(try handleKey(.{ .codepoint = '/' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.SEARCH, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'l',
        .text = "l",
    }, &document, &editor_state, allocator)));
    try testing.expect(!editor_state.invalid_search);
    try testing.expectEqual(14, document.cursor_x);
    try testing.expectEqual(0, document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expectEqual(.NORMAL, document.mode);
    try testing.expect(editor_state.invalid_search);
    try testing.expectEqual(14, document.cursor_x);
    try testing.expectEqual(0, document.cursor_y);
}

test "searching forward" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "quit zag with wq or q or q!");
    try document.appendRow(allocator, "quit zag with wq or q or q!");

    try testing.expect(!(try handleKey(.{ .codepoint = '/' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.SEARCH, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'q',
        .text = "q",
    }, &document, &editor_state, allocator)));
    try testing.expect(!editor_state.invalid_search);
    try testing.expectEqual(14, document.cursor_x);
    try testing.expectEqual(0, document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expectEqual(.NORMAL, document.mode);
    try testing.expect(!editor_state.invalid_search);
    try testing.expect(!(try handleKey(.{ .codepoint = 'n' }, &document, &editor_state, allocator)));
    try testing.expectEqual(14, document.cursor_x);
    try testing.expectEqual(1, document.cursor_y);
}

test "searching back" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "quit zag with wq or q or q!");
    try document.appendRow(allocator, "quit zag with wq or q or q!");
    document.cursor_x = 13;
    document.cursor_y = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = '/' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.SEARCH, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'q',
        .text = "q",
    }, &document, &editor_state, allocator)));
    try testing.expect(!editor_state.invalid_search);
    try testing.expectEqual(14, document.cursor_x);
    try testing.expectEqual(1, document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expectEqual(.NORMAL, document.mode);
    try testing.expect(!editor_state.invalid_search);
    try testing.expect(!(try handleKey(.{ .codepoint = 'N' }, &document, &editor_state, allocator)));
    try testing.expectEqual(14, document.cursor_x);
    try testing.expectEqual(0, document.cursor_y);
}

test "searching between two occurences" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "quit zag with wq or q or q!");
    try document.appendRow(allocator, "something else");
    try document.appendRow(allocator, "quit zag with wq or q or q!");
    document.cursor_x = 5;
    document.cursor_y = 1;

    try testing.expect(!(try handleKey(.{ .codepoint = '/' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.SEARCH, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'q',
        .text = "q",
    }, &document, &editor_state, allocator)));
    try testing.expect(!editor_state.invalid_search);
    try testing.expectEqual(14, document.cursor_x);
    try testing.expectEqual(2, document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expectEqual(.NORMAL, document.mode);
    try testing.expect(!editor_state.invalid_search);
    try testing.expectEqual(14, document.cursor_x);
    try testing.expectEqual(2, document.cursor_y);
}

test "searching under cursor" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "quit zag with wq or q or q!");
    try document.appendRow(allocator, "something else");
    try document.appendRow(allocator, "quit zag with wq or q or q!");
    document.cursor_x = 14;
    document.cursor_y = 0;

    try testing.expect(!(try handleKey(.{ .codepoint = '/' }, &document, &editor_state, allocator)));
    try testing.expectEqual(.SEARCH, document.mode);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'q',
        .text = "q",
    }, &document, &editor_state, allocator)));
    try testing.expect(!editor_state.invalid_search);
    try testing.expectEqual(14, document.cursor_x);
    try testing.expectEqual(0, document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.enter }, &document, &editor_state, allocator)));
    try testing.expectEqual(.NORMAL, document.mode);
    try testing.expect(!editor_state.invalid_search);
    try testing.expectEqual(14, document.cursor_x);
    try testing.expectEqual(0, document.cursor_y);
}

// REPLACE MODE
test "replacing text with r" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "hello");

    document.cursor_y = 0;
    document.cursor_x = 0;
    try testing.expect(!(try handleKey(.{ .codepoint = 'r' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .REPLACE);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expectEqualStrings("wello", document.rows.items[0].chars.items);

    try document.appendRow(allocator, "");
    document.cursor_y = 1;
    try testing.expect(!(try handleKey(.{ .codepoint = 'r' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .REPLACE);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expectEqualStrings("", document.rows.items[1].chars.items);
}

test "replacing text with R" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "hello");

    document.cursor_y = 0;
    document.cursor_x = 0;
    try testing.expect(!(try handleKey(.{ .codepoint = 'R' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .REPLACE);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'o',
        .text = "o",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'r',
        .text = "r",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'l',
        .text = "l",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'd',
        .text = "d",
    }, &document, &editor_state, allocator)));
    // this should not show in the line since it's greater than the length of the row
    try testing.expect(!(try handleKey(.{
        .codepoint = '.',
        .text = ".",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expectEqualStrings("world", document.rows.items[0].chars.items);

    try document.appendRow(allocator, "");
    document.cursor_y = 1;
    try testing.expect(!(try handleKey(.{ .codepoint = 'R' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .REPLACE);
    try testing.expect(!(try handleKey(.{
        .codepoint = 'w',
        .text = "w",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expectEqualStrings("", document.rows.items[1].chars.items);
}

// MOTIONS WITH DIGITS
test "keys append to state" {
    const allocator = testing.allocator;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try testing.expect(!(try handleKey(.{
        .codepoint = '3',
        .text = "3",
    }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{
        .codepoint = 'd',
        .text = "d",
    }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("3d", editor_state.pending_motion[0..editor_state.pending_motion_len]);

    // essentially resets our array to blank
    // replaces first char with new key and we only look at that char
    // good enough for testing
    editor_state.pending_motion_len = 0;
    try testing.expect(!(try handleKey(.{
        .codepoint = 'g',
        .text = "g",
    }, &document, &editor_state, allocator)));
    try testing.expectEqualStrings("g", editor_state.pending_motion[0..editor_state.pending_motion_len]);
}
