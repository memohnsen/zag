const std = @import("std");

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

/// Input is the bytes of the char pressed
pub fn ctrlKey(input: u8) u8 {
    return input & 0x1f;
}
