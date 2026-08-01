const std = @import("std");

const rawmode = @import("rawmode.zig");
const ui = @import("ui.zig");
const input = @import("input.zig");
const editor = @import("editor.zig");

// our connection to the terminal
const stdin_fd = std.posix.STDIN_FILENO;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var editor_main = editor.Editor{};
    defer editor_main.deinit(gpa);
    try editor_main.appendRow(gpa, "Hello, zag");

    // get original terminal attributes so we can reset it once user exits
    const original_termios = try std.posix.tcgetattr(stdin_fd);
    try rawmode.enableRawMode(original_termios);
    defer std.posix.tcsetattr(stdin_fd, .FLUSH, original_termios) catch {};
    defer ui.clearScreen(io) catch {};

    const terminal_size = try ui.getTerminalSize(io);
    var cursor_x: usize = 0;
    var cursor_y: usize = 0;
    var waiting_for_gg = false;

    std.debug.print("Raw mode active. Press 'C-q' to exit\r\n", .{});

    while (true) {
        try ui.refreshScreen(io, terminal_size, gpa, cursor_x, cursor_y, &editor_main);
        const key = try input.readKey();
        switch (key) {
            .byte => |byte| {
                if (byte == input.ctrlKey('q')) break;
                if (byte == 'g') {
                    if (waiting_for_gg) {
                        cursor_y = 0;
                        waiting_for_gg = false;
                    } else {
                        waiting_for_gg = true;
                    }
                } else {
                    if (byte == 'G') {
                        cursor_y = terminal_size.rows - 1;
                    }
                    waiting_for_gg = false;
                }
                if (byte == '0') {
                    cursor_x = 0;
                }
                if (byte == '$') {
                    cursor_x = terminal_size.columns - 1;
                }
            },
            .arrow_left => {
                if (cursor_x > 0) cursor_x -= 1;
                waiting_for_gg = false;
            },
            .arrow_down => {
                if (cursor_y + 1 < terminal_size.rows) cursor_y += 1;
                waiting_for_gg = false;
            },
            .arrow_up => {
                if (cursor_y > 0) cursor_y -= 1;
                waiting_for_gg = false;
            },
            .arrow_right => {
                if (cursor_x + 1 < terminal_size.columns) cursor_x += 1;
                waiting_for_gg = false;
            },
            .delete => {
                waiting_for_gg = false;
            },
        }
    }
}
