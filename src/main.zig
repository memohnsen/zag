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
    try editor_main.appendRow(gpa, "zag");

    // get original terminal attributes so we can reset it once user exits
    const original_termios = try std.posix.tcgetattr(stdin_fd);
    try rawmode.enableRawMode(original_termios);
    defer std.posix.tcsetattr(stdin_fd, .FLUSH, original_termios) catch {};
    defer ui.clearScreen(io) catch {};

    const terminal_size = try ui.getTerminalSize(io);
    var waiting_for_gg = false;
    var exit_editor = false;

    while (!exit_editor) {
        try ui.refreshScreen(io, terminal_size, gpa, editor_main.cursor_x, editor_main.cursor_y, &editor_main);
        const key = try input.readKey();
        input.handleKey(key, &waiting_for_gg, &editor_main, &exit_editor);
    }
}
