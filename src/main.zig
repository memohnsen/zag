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
    try event_loop.installResizeHandler();
    defer event_loop.uninstallResizeHandler();
    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));

    var command_state: commands.State = .{};

    while (true) {
        const event = try event_loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (commands.handleKey(key, &ed, &command_state)) break;
            },
            .winsize => |size| {
                try vx.resize(gpa, tty.writer(), size);
            },
        }

        const window = vx.window();
        ed.scroll(window.height, window.width);
        try ui.refresh(&vx, tty.writer(), &ed);
    }
}
