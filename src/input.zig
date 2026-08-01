const std = @import("std");
const editor = @import("editor.zig");

const stdin_fd = std.posix.STDIN_FILENO;

pub const Key = union(enum) { byte: u8, arrow_up, arrow_down, arrow_left, arrow_right, delete };

pub fn readKey() !Key {
    var buf: [1]u8 = undefined;
    while (true) {
        // read terminal input and pass into our buffer
        const n = try std.posix.read(stdin_fd, &buf);
        if (n > 0) {
            const first = buf[0];
            // 0x1b is the escape sequence meaning more is coming
            if (first != 0x1b) {
                return .{ .byte = first };
            } else {
                var buf2: [1]u8 = undefined;
                const second = try std.posix.read(stdin_fd, &buf2);
                // check for [ for continuation of sequence
                if (second == 1) {
                    if (buf2[0] != '[') {
                        return .{ .byte = first };
                    } else {
                        var buf3: [1]u8 = undefined;
                        const third = try std.posix.read(stdin_fd, &buf3);
                        // map to the final key in the sequence
                        if (third == 1) {
                            return switch (buf3[0]) {
                                'A' => .arrow_up,
                                'B' => .arrow_down,
                                'C' => .arrow_right,
                                'D' => .arrow_left,
                                '3' => {
                                    var buf4: [1]u8 = undefined;
                                    const fourth = try std.posix.read(stdin_fd, &buf4);
                                    // map to the final key in the sequence
                                    if (fourth == 1) {
                                        if (buf4[0] == '~') {
                                            return .delete;
                                        } else {
                                            return .{ .byte = first };
                                        }
                                    } else {
                                        return .{ .byte = first };
                                    }
                                },
                                else => .{ .byte = first },
                            };
                        }
                    }
                }
            }
            return .{ .byte = first };
        }
    }
}

pub fn handleKey(key: Key, waiting_for_gg: *bool, editor_main: *editor.Editor, exit_editor: *bool) void {
    switch (key) {
        .byte => |byte| {
            if (byte == ctrlKey('q')) exit_editor.* = true;
            if (byte == 'g') {
                if (waiting_for_gg.*) {
                    editor_main.cursor_y = 0;
                    waiting_for_gg.* = false;
                } else {
                    waiting_for_gg.* = true;
                }
            } else {
                if (byte == 'G') {
                    if (editor_main.rows.items.len != 0) {
                        editor_main.cursor_y = editor_main.rows.items.len - 1;
                    }
                }
                waiting_for_gg.* = false;
            }
            if (byte == '0') {
                editor_main.cursor_x = 0;
            }
            if (byte == '$') {
                if (editor_main.currentRow()) |row| {
                    if (row.chars.len > 0) {
                        editor_main.cursor_x = row.chars.len - 1;
                    } else {
                        editor_main.cursor_x = 0;
                    }
                } else {
                    editor_main.cursor_x = 0;
                }
            }
        },
        .arrow_left => {
            if (editor_main.cursor_x > 0) editor_main.cursor_x -= 1;
            waiting_for_gg.* = false;
        },
        .arrow_down => {
            if (editor_main.cursor_y + 1 < editor_main.rows.items.len) editor_main.cursor_y += 1;
            waiting_for_gg.* = false;
        },
        .arrow_up => {
            if (editor_main.cursor_y > 0) editor_main.cursor_y -= 1;
            waiting_for_gg.* = false;
        },
        .arrow_right => {
            if (editor_main.currentRow()) |row| {
                if (editor_main.cursor_x + 1 < row.chars.len) {
                    editor_main.cursor_x += 1;
                }
            }
            waiting_for_gg.* = false;
        },
        .delete => {
            waiting_for_gg.* = false;
        },
    }

    if (editor_main.currentRow()) |row| {
        const row_len = row.chars.len;
        if (row_len == 0) {
            editor_main.cursor_x = 0;
        } else if (editor_main.cursor_x >= row_len) {
            editor_main.cursor_x = row_len - 1;
        }
    } else {
        editor_main.cursor_x = 0;
    }
}

/// Input is the bytes of the char pressed
pub fn ctrlKey(input: u8) u8 {
    return input & 0x1f;
}
