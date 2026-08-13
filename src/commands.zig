const std = @import("std");
const mem = std.mem;
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
    first_char,
    line_start,
    line_end,
    middle,
    page_down,
    page_up,
    next_word_start,
    next_word_end,
    last_word_start,
    next_space_start,
    next_space_end,
    last_space_start,

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
    // load pending editor_state into a const so we don't have to false it every branch
    const pending_g = editor_state.pending_g;
    editor_state.pending_g = false;
    const pending_d = editor_state.pending_d;
    editor_state.pending_d = false;

    const command = commandFromKey(key, document, pending_g);

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
        .first_char => {
            if (std.mem.indexOfNone(u8, document.rows.items[document.cursor_y].render.items, " \t\r\n")) |pos| {
                document.cursor_x = pos;
            } else {
                document.cursor_x = 0;
            }
            editor_state.pending_g = false;
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
            document.cursor_y = document.row_offset + document.rows_shown / 2;
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
        // TODO: get pos of chars to do this
        .next_word_start => {},
        .next_word_end => {},
        .last_word_start => {},
        .next_space_start => {},
        .next_space_end => {},
        .last_space_start => {},

        // MODES
        .normal => {
            if (document.mode == .SEARCH) {
                document.cursor_x = editor_state.cursor_origin_x;
                document.cursor_y = editor_state.cursor_origin_y;
            }
            editor_state.clearText(document);
            editor_state.replace_mult = false;
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
            if (std.mem.eql(u8, editor_state.command_buffer.items, ":w")) {
                editor_state.save_requested = true;
                editor_state.clearText(document);
            } else if (std.mem.eql(u8, editor_state.command_buffer.items, ":wq")) {
                editor_state.save_requested = true;
                return true;
            } else if (std.mem.startsWith(u8, editor_state.command_buffer.items, ":w ")) {
                if (editor_state.command_buffer.items.len > 3) {
                    const args = editor_state.command_buffer.items[3..];
                    const filename = std.mem.trim(u8, args, " ");
                    if (filename.len > 0) {
                        try document.setFilenameAs(allocator, filename);
                    }
                }

                editor_state.save_requested = true;
                editor_state.clearText(document);
            } else if (std.mem.eql(u8, editor_state.command_buffer.items, ":q") and !document.unsaved_edits) {
                return true;
            } else if (std.mem.eql(u8, editor_state.command_buffer.items, ":q!")) {
                return true;
            } else if (std.mem.eql(u8, editor_state.command_buffer.items, ":q") and document.unsaved_edits) {
                editor_state.quit_blocked = true;
            } else {
                editor_state.invalid_command = true;
            }
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
        },
        .delete_current => {
            if (document.currentRow()) |row| {
                if (document.cursor_x < row.chars.items.len) {
                    try row.removeByte(document.cursor_x, allocator);
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
            try document.deleteRemainingLine(allocator);
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

    clampCursorX(document);
    return false;
}

fn commandFromKey(key: vaxis.Key, document: *editor.Editor, pending_g: bool) Command {
    if (key.matches(vaxis.Key.escape, .{}) and document.mode != .NORMAL) return .normal;

    // NAVIGATION
    if (key.matches('G', .{}) and document.mode == .NORMAL) return .document_end;
    if (key.matches('0', .{}) and document.mode == .NORMAL) return .line_start;
    if (key.matches('h', .{}) and document.mode == .NORMAL and pending_g) return .first_char;
    if (key.matches('_', .{}) and document.mode == .NORMAL) return .first_char;
    if (key.matches('$', .{}) and document.mode == .NORMAL) return .line_end;
    if (key.matches('l', .{}) and document.mode == .NORMAL and pending_g) return .line_end;
    if (key.matches('g', .{}) and document.mode == .NORMAL) return .doc_start_gg;
    if (key.matches('M', .{}) and document.mode == .NORMAL) return .middle;
    if (key.matches('d', .{ .ctrl = true }) and document.mode == .NORMAL) return .page_down;
    if (key.matches('u', .{ .ctrl = true }) and document.mode == .NORMAL) return .page_up;
    // TODO: ----------------
    if (key.matches('w', .{}) and document.mode == .NORMAL) return .next_word_start;
    if (key.matches('W', .{}) and document.mode == .NORMAL) return .next_space_start;
    if (key.matches('e', .{}) and document.mode == .NORMAL) return .next_word_end;
    if (key.matches('E', .{}) and document.mode == .NORMAL) return .next_space_end;
    if (key.matches('b', .{}) and document.mode == .NORMAL) return .last_word_start;
    if (key.matches('B', .{}) and document.mode == .NORMAL) return .last_space_start;
    // ----------------------
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
    if (key.matches(vaxis.Key.backspace, .{}) and (document.mode == .INSERT or document.mode == .COMMAND or document.mode == .SEARCH)) return .delete_left;
    if (key.matches('x', .{}) and document.mode == .NORMAL) return .delete_current;
    if (key.matches('X', .{}) and document.mode == .NORMAL) return .delete_left;
    if (key.matches('d', .{}) and document.mode == .NORMAL) return .delete_line;
    if (key.matches('D', .{}) and document.mode == .NORMAL) return .delete_line_remaining;

    // MODES
    if (key.matches('r', .{}) and document.mode == .NORMAL) return .replace;
    if (key.matches('R', .{}) and document.mode == .NORMAL) return .replace_mult;
    if (key.matches('v', .{}) and document.mode == .NORMAL) return .visual;
    if (key.matches('V', .{}) and document.mode == .NORMAL) return .visual;
    if (key.matches(':', .{}) and document.mode == .NORMAL) return .command;
    if (key.matches(vaxis.Key.enter, .{}) and document.mode == .COMMAND) return .run_command;
    if (key.matches('/', .{}) and document.mode == .NORMAL) return .search;
    if (key.matches('n', .{}) and document.mode == .NORMAL) return .search_next;
    if (key.matches('N', .{}) and document.mode == .NORMAL) return .search_prev;
    if (key.matches(vaxis.Key.enter, .{}) and document.mode == .SEARCH) return .run_search;

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
    try testing.expect(!(try handleKey(.{ .codepoint = 'u', .mods = .{ .ctrl = true } }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_y == 5);
    try testing.expect(!(try handleKey(.{ .codepoint = 'u', .mods = .{ .ctrl = true } }, &document, &editor_state, allocator)));
    try testing.expect(document.cursor_y == 0);
    try testing.expect(!(try handleKey(.{ .codepoint = 'u', .mods = .{ .ctrl = true } }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'd', .mods = .{ .ctrl = true } }, &document, &editor_state, allocator)));
    try testing.expectEqual(5, document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = 'd', .mods = .{ .ctrl = true } }, &document, &editor_state, allocator)));
    try testing.expectEqual(10, document.cursor_y);
    try testing.expect(!(try handleKey(.{ .codepoint = 'd', .mods = .{ .ctrl = true } }, &document, &editor_state, allocator)));
    try testing.expectEqual(10, document.cursor_y);
}

test "M jumps to midscreen" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);
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

test ":q quits with no unsaved edits" {
    const allocator = testing.allocator;
    var editor_state = state.State{};
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    defer editor_state.deinit(allocator);

    try testing.expect(!editor_state.quit_blocked);
    try testing.expect(!(try handleKey(.{ .codepoint = ':' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .COMMAND);
    try testing.expect(!(try handleKey(.{ .codepoint = 'q', .text = "q" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'q', .text = "q" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'q', .text = "q" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = '!', .text = "!" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'q', .text = "q" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = '!', .text = "!" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = ' ', .text = " " }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'a', .text = "a" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'o', .text = "o" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'l', .text = "l" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'o', .text = "o" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'q', .text = "q" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'q', .text = "q" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'l', .text = "l" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'q', .text = "q" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'q', .text = "q" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'q', .text = "q" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'q', .text = "q" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expectEqualStrings("wello", document.rows.items[0].chars.items);

    try document.appendRow(allocator, "");
    document.cursor_y = 1;
    try testing.expect(!(try handleKey(.{ .codepoint = 'r' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .REPLACE);
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
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
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'o', .text = "o" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'r', .text = "r" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'l', .text = "l" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = 'd', .text = "d" }, &document, &editor_state, allocator)));
    // this should not show in the line since it's greater than the length of the row
    try testing.expect(!(try handleKey(.{ .codepoint = '.', .text = "." }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expectEqualStrings("world", document.rows.items[0].chars.items);

    try document.appendRow(allocator, "");
    document.cursor_y = 1;
    try testing.expect(!(try handleKey(.{ .codepoint = 'R' }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .REPLACE);
    try testing.expect(!(try handleKey(.{ .codepoint = 'w', .text = "w" }, &document, &editor_state, allocator)));
    try testing.expect(!(try handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &editor_state, allocator)));
    try testing.expect(document.mode == .NORMAL);
    try testing.expectEqualStrings("", document.rows.items[1].chars.items);
}
