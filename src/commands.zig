const std = @import("std");
const vaxis = @import("vaxis");

const editor = @import("editor.zig");

pub const State = struct {
    pending_g: bool = false,
};

const Command = enum {
    quit,
    left,
    right,
    up,
    down,
    first_g,
    document_end,
    line_start,
    line_end,
    other,
};

pub fn handleKey(key: vaxis.Key, ed: *editor.Editor, state: *State) bool {
    const command = commandFromKey(key);

    switch (command) {
        .quit => return true,
        .left => {
            if (ed.cursor_x > 0) ed.cursor_x -= 1;
            state.pending_g = false;
        },
        .right => {
            if (ed.currentRow()) |row| {
                if (ed.cursor_x + 1 < row.chars.len) ed.cursor_x += 1;
            }
            state.pending_g = false;
        },
        .up => {
            if (ed.cursor_y > 0) ed.cursor_y -= 1;
            state.pending_g = false;
        },
        .down => {
            if (ed.cursor_y + 1 < ed.rows.items.len) ed.cursor_y += 1;
            state.pending_g = false;
        },
        .first_g => {
            if (state.pending_g) {
                ed.cursor_y = 0;
                state.pending_g = false;
            } else {
                state.pending_g = true;
            }
        },
        .document_end => {
            if (ed.rows.items.len > 0) ed.cursor_y = ed.rows.items.len - 1;
            state.pending_g = false;
        },
        .line_start => {
            ed.cursor_x = 0;
            state.pending_g = false;
        },
        .line_end => {
            if (ed.currentRow()) |row| {
                ed.cursor_x = if (row.chars.len == 0) 0 else row.chars.len - 1;
            } else {
                ed.cursor_x = 0;
            }
            state.pending_g = false;
        },
        .other => state.pending_g = false,
    }

    clampCursorX(ed);
    return false;
}

fn commandFromKey(key: vaxis.Key) Command {
    if (key.matches('q', .{ .alt = true })) return .quit;
    if (key.matches('G', .{})) return .document_end;
    if (key.matches('$', .{})) return .line_end;
    if (key.matches('g', .{})) return .first_g;
    if (key.matches('0', .{})) return .line_start;

    return switch (key.codepoint) {
        vaxis.Key.left => .left,
        vaxis.Key.right => .right,
        vaxis.Key.up => .up,
        vaxis.Key.down => .down,
        else => .other,
    };
}

fn clampCursorX(ed: *editor.Editor) void {
    const row = ed.currentRow() orelse {
        ed.cursor_x = 0;
        return;
    };

    if (row.chars.len == 0) {
        ed.cursor_x = 0;
    } else if (ed.cursor_x >= row.chars.len) {
        ed.cursor_x = row.chars.len - 1;
    }
}

test "alt-q quits" {
    var ed: editor.Editor = .{};
    var state: State = .{};
    const key: vaxis.Key = .{ .codepoint = 'q', .mods = .{ .alt = true } };

    try std.testing.expect(handleKey(key, &ed, &state));
}

test "gg and G move to document boundaries" {
    const allocator = std.testing.allocator;
    var ed: editor.Editor = .{};
    defer ed.deinit(allocator);
    var state: State = .{};

    try ed.appendRow(allocator, "first");
    try ed.appendRow(allocator, "second");
    try ed.appendRow(allocator, "third");

    try std.testing.expect(!handleKey(.{ .codepoint = 'G' }, &ed, &state));
    try std.testing.expectEqual(@as(usize, 2), ed.cursor_y);

    try std.testing.expect(!handleKey(.{ .codepoint = 'g' }, &ed, &state));
    try std.testing.expect(state.pending_g);
    try std.testing.expect(!handleKey(.{ .codepoint = 'g' }, &ed, &state));
    try std.testing.expectEqual(@as(usize, 0), ed.cursor_y);
    try std.testing.expect(!state.pending_g);
}
