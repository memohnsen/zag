const vaxis = @import("vaxis");
const editor = @import("editor.zig");

pub fn handleVaxisKey(
    key: vaxis.Key,
    exit_editor: *bool,
    ed: *editor.Editor,
    pending_g: *bool,
) void {
    if (key.matches('q', .{ .alt = true })) {
        exit_editor.* = true;
        return;
    }

    switch (key.codepoint) {
        vaxis.Key.left => {
            if (ed.cursor_x > 0) ed.cursor_x -= 1;
            pending_g.* = false;
        },
        vaxis.Key.right => {
            if (ed.currentRow()) |row| {
                if (ed.cursor_x + 1 < row.chars.len) {
                    ed.cursor_x += 1;
                }
            }
            pending_g.* = false;
        },
        vaxis.Key.up => {
            if (ed.cursor_y > 0) ed.cursor_y -= 1;
            pending_g.* = false;
        },
        vaxis.Key.down => {
            if (ed.cursor_y + 1 < ed.rows.items.len) ed.cursor_y += 1;
            pending_g.* = false;
        },
        'g' => {
            if (pending_g.*) {
                ed.cursor_y = 0;
                pending_g.* = false;
            } else {
                pending_g.* = true;
            }
        },
        'G' => {
            if (ed.rows.items.len != 0) {
                ed.cursor_y = ed.rows.items.len - 1;
            }
            pending_g.* = false;
        },
        '0' => {
            ed.cursor_x = 0;
            pending_g.* = false;
        },
        '$' => {
            if (ed.currentRow()) |row| {
                if (row.chars.len > 0) {
                    ed.cursor_x = row.chars.len - 1;
                } else {
                    ed.cursor_x = 0;
                }
            } else {
                ed.cursor_x = 0;
            }
            pending_g.* = false;
        },
        else => {
            pending_g.* = false;
        },
    }

    if (ed.currentRow()) |row| {
        const row_len = row.chars.len;
        if (row_len == 0) {
            ed.cursor_x = 0;
        } else if (ed.cursor_x >= row_len) {
            ed.cursor_x = row_len - 1;
        }
    } else {
        ed.cursor_x = 0;
    }
}
