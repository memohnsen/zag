const std = @import("std");
const vaxis = @import("vaxis");

const editor = @import("editor.zig");

pub const State = struct {
    pending_g: bool = false,
};

const Command = enum {
    quit,

    // NAVIGATION
    left,
    right,
    up,
    down,
    doc_start_gg,
    document_end,
    line_start,
    line_end,

    // MODES
    insert,
    normal,
    command,
    visual,
    replace,

    other,
};

pub fn handleKey(key: vaxis.Key, document: *editor.Editor, state: *State) bool {
    // load pending state into a const so we don't have to false it every branch
    const pending_g = state.pending_g;
    state.pending_g = false;

    const command = commandFromKey(key, document, pending_g);

    switch (command) {
        .quit => return true,

        // NAVIGATION
        .left => {
            if (document.cursor_x > 0) document.cursor_x -= 1;
        },
        .right => {
            if (document.currentRow()) |row| {
                if (document.cursor_x + 1 < row.chars.len) document.cursor_x += 1;
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
                state.pending_g = false;
            } else {
                state.pending_g = true;
            }
        },
        .document_end => {
            if (document.rows.items.len > 0) document.cursor_y = document.rows.items.len - 1;
        },
        .line_start => {
            document.cursor_x = 0;
            state.pending_g = false;
        },
        .line_end => {
            if (document.currentRow()) |row| {
                document.cursor_x = if (row.chars.len == 0) 0 else row.chars.len - 1;
            } else {
                document.cursor_x = 0;
            }
            state.pending_g = false;
        },

        // MODES
        .normal => document.mode = .normal,
        .insert => document.mode = .insert,
        .visual => document.mode = .visual,
        .command => document.mode = .command,
        .replace => document.mode = .replace,

        .other => state.pending_g = false,
    }

    clampCursorX(document);
    return false;
}

fn commandFromKey(key: vaxis.Key, document: *editor.Editor, pending_g: bool) Command {
    if (key.matches('q', .{ .ctrl = true })) return .quit;

    // NAVIGATION
    if (key.matches('G', .{}) and document.mode == .normal) return .document_end;
    if (key.matches('0', .{}) and document.mode == .normal) return .line_start;
    if (key.matches('h', .{}) and document.mode == .normal and pending_g) return .line_start;
    if (key.matches('$', .{}) and document.mode == .normal) return .line_end;
    if (key.matches('l', .{}) and document.mode == .normal and pending_g) return .line_end;
    if (key.matches('g', .{}) and document.mode == .normal) return .doc_start_gg;

    if (key.matches('h', .{}) and document.mode == .normal) return .left;
    if (key.matches('j', .{}) and document.mode == .normal) return .down;
    if (key.matches('k', .{}) and document.mode == .normal) return .up;
    if (key.matches('l', .{}) and document.mode == .normal) return .right;

    // MODES
    if (key.matches('i', .{}) and document.mode == .normal) return .insert;
    if (key.matches('I', .{}) and document.mode == .normal) return .insert;
    if (key.matches('a', .{}) and document.mode == .normal) return .insert;
    if (key.matches('A', .{}) and document.mode == .normal) return .insert;

    if (key.matches('r', .{}) and document.mode == .normal) return .replace;
    if (key.matches('R', .{}) and document.mode == .normal) return .replace;

    if (key.matches('v', .{}) and document.mode == .normal) return .visual;
    if (key.matches('V', .{}) and document.mode == .normal) return .visual;

    if (key.matches(vaxis.Key.escape, .{}) and document.mode != .normal) return .normal;

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

    if (row.chars.len == 0) {
        document.cursor_x = 0;
    } else if (document.cursor_x >= row.chars.len) {
        document.cursor_x = row.chars.len - 1;
    }
}

test "ctrl-q quits" {
    var document: editor.Editor = .{};
    var state: State = .{};
    const key: vaxis.Key = .{ .codepoint = 'q', .mods = .{ .ctrl = true } };

    try std.testing.expect(handleKey(key, &document, &state));
}

test "gg and G move to document boundaries" {
    const allocator = std.testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var state: State = .{};

    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "second");
    try document.appendRow(allocator, "third");

    try std.testing.expect(!handleKey(.{ .codepoint = 'G' }, &document, &state));
    try std.testing.expectEqual(@as(usize, 2), document.cursor_y);

    try std.testing.expect(!handleKey(.{ .codepoint = 'g' }, &document, &state));
    try std.testing.expect(state.pending_g);
    try std.testing.expect(!handleKey(.{ .codepoint = 'g' }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_y);
    try std.testing.expect(!state.pending_g);
}

test "0 and gh move to line start" {
    const allocator = std.testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var state: State = .{};

    try document.appendRow(allocator, "first");

    document.cursor_x = 3;
    try std.testing.expect(!handleKey(.{ .codepoint = '0' }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_x);

    document.cursor_x = 3;
    try std.testing.expect(!handleKey(.{ .codepoint = 'g' }, &document, &state));
    try std.testing.expect(state.pending_g);
    try std.testing.expect(!handleKey(.{ .codepoint = 'h' }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_x);
}

test "$ and gl move to line end" {
    const allocator = std.testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var state: State = .{};

    try document.appendRow(allocator, "first");

    try std.testing.expect(!handleKey(.{ .codepoint = '$' }, &document, &state));
    try std.testing.expectEqual(@as(usize, 4), document.cursor_x);

    document.cursor_x = 0;
    try std.testing.expect(!handleKey(.{ .codepoint = 'g' }, &document, &state));
    try std.testing.expect(state.pending_g);
    try std.testing.expect(!handleKey(.{ .codepoint = 'l' }, &document, &state));
    try std.testing.expectEqual(@as(usize, 4), document.cursor_x);
}

test "hjkl work for movement in normal mode" {
    const allocator = std.testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var state: State = .{};

    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "second");
    try document.appendRow(allocator, "third");

    try std.testing.expect(document.mode == .normal);
    try std.testing.expect(!handleKey(.{ .codepoint = 'l' }, &document, &state));
    try std.testing.expectEqual(@as(usize, 1), document.cursor_x);
    try std.testing.expect(!handleKey(.{ .codepoint = 'h' }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_x);
    try std.testing.expect(!handleKey(.{ .codepoint = 'j' }, &document, &state));
    try std.testing.expectEqual(@as(usize, 1), document.cursor_y);
    try std.testing.expect(!handleKey(.{ .codepoint = 'k' }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_y);

    document.mode = .insert;
    try std.testing.expect(!handleKey(.{ .codepoint = 'l' }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_x);
    try std.testing.expect(!handleKey(.{ .codepoint = 'h' }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_x);
    try std.testing.expect(!handleKey(.{ .codepoint = 'j' }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_y);
    try std.testing.expect(!handleKey(.{ .codepoint = 'k' }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_y);
}

test "arrows work for movement in all modes" {
    const allocator = std.testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var state: State = .{};

    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "second");
    try document.appendRow(allocator, "third");

    try std.testing.expect(document.mode == .normal);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.right }, &document, &state));
    try std.testing.expectEqual(@as(usize, 1), document.cursor_x);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.left }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_x);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.down }, &document, &state));
    try std.testing.expectEqual(@as(usize, 1), document.cursor_y);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.up }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_y);

    document.mode = .insert;
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.right }, &document, &state));
    try std.testing.expectEqual(@as(usize, 1), document.cursor_x);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.left }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_x);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.down }, &document, &state));
    try std.testing.expectEqual(@as(usize, 1), document.cursor_y);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.up }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_y);

    document.mode = .visual;
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.right }, &document, &state));
    try std.testing.expectEqual(@as(usize, 1), document.cursor_x);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.left }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_x);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.down }, &document, &state));
    try std.testing.expectEqual(@as(usize, 1), document.cursor_y);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.up }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_y);

    document.mode = .replace;
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.right }, &document, &state));
    try std.testing.expectEqual(@as(usize, 1), document.cursor_x);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.left }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_x);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.down }, &document, &state));
    try std.testing.expectEqual(@as(usize, 1), document.cursor_y);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.up }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_y);

    document.mode = .command;
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.right }, &document, &state));
    try std.testing.expectEqual(@as(usize, 1), document.cursor_x);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.left }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_x);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.down }, &document, &state));
    try std.testing.expectEqual(@as(usize, 1), document.cursor_y);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.up }, &document, &state));
    try std.testing.expectEqual(@as(usize, 0), document.cursor_y);
}

test "modes change" {
    const allocator = std.testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var state: State = .{};

    try document.appendRow(allocator, "first");
    try document.appendRow(allocator, "second");
    try document.appendRow(allocator, "third");

    try std.testing.expect(document.mode == .normal);
    try std.testing.expect(!handleKey(.{ .codepoint = 'i' }, &document, &state));
    try std.testing.expect(document.mode == .insert);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &state));
    try std.testing.expect(!handleKey(.{ .codepoint = 'a' }, &document, &state));
    try std.testing.expect(document.mode == .insert);

    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &state));
    try std.testing.expect(document.mode == .normal);
    try std.testing.expect(!handleKey(.{ .codepoint = 'r' }, &document, &state));
    try std.testing.expect(document.mode == .replace);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &state));
    try std.testing.expect(document.mode == .normal);
    try std.testing.expect(!handleKey(.{ .codepoint = 'R' }, &document, &state));
    try std.testing.expect(document.mode == .replace);

    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &state));
    try std.testing.expect(document.mode == .normal);
    try std.testing.expect(!handleKey(.{ .codepoint = 'v' }, &document, &state));
    try std.testing.expect(document.mode == .visual);
    try std.testing.expect(!handleKey(.{ .codepoint = vaxis.Key.escape }, &document, &state));
    try std.testing.expect(document.mode == .normal);
    try std.testing.expect(!handleKey(.{ .codepoint = 'V' }, &document, &state));
    try std.testing.expect(document.mode == .visual);
}
