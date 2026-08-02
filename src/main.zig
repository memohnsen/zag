const std = @import("std");

const vaxis = @import("vaxis");
const ui = @import("ui.zig");
const editor = @import("editor.zig");
const commands = @import("commands.zig");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var ed = editor.Editor{};
    defer ed.deinit(gpa);

    var tty_buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &tty_buffer);
    defer tty.deinit();
    var vx = try vaxis.init(io, gpa, init.environ_map, .{});
    defer vx.deinit(gpa, tty.writer());

    var event_loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
    try event_loop.start();
    defer event_loop.stop();

    defer ui.clearScreen(io) catch {};

    const terminal_size = try ui.getTerminalSize(io);
    var pending_g = false;
    var exit_editor = false;

    while (!exit_editor) {
        ed.scroll(terminal_size.rows, terminal_size.columns);
        try ui.refreshScreen(io, terminal_size, gpa, ed.cursor_x, ed.cursor_y, &ed);

        const event = try event_loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                commands.handleVaxisKey(key, &exit_editor, &ed, &pending_g);
            },
            .winsize => {},
        }
    }
}
