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

    // Get args and skip the first
    const args = init.minimal.args;
    var iter = try args.iterateAllocator(gpa);
    defer iter.deinit();
    _ = iter.skip();

    if (iter.next()) |filename| {
        const cwd = std.Io.Dir.cwd();
        const file = try cwd.openFile(io, filename, .{});
        defer file.close(io);

        // Must duplicate this since the iter owns the original filename
        const stored_filename = try gpa.dupe(u8, filename);
        ed.filename = stored_filename;

        // Create a buffer to store contents, alloc the remaining, then append to view
        var buf: [4096]u8 = undefined;
        var reader = file.reader(io, &buf);
        const contents = try reader.interface.allocRemaining(gpa, .limited(10 * 1024 * 1024));
        defer gpa.free(contents);

        var rows = std.mem.splitScalar(u8, contents, '\n');

        while (rows.next()) |row| {
            const trimmed = std.mem.trimEnd(u8, row, "\r");
            try ed.appendRow(gpa, trimmed);
        }
    }

    // Set up vaxis and the terminal
    var tty_buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &tty_buffer);
    defer tty.deinit();
    var vx = try vaxis.init(io, gpa, init.environ_map, .{});
    defer vx.deinit(gpa, tty.writer());

    // Set up vaxis to run terminal and get keys
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
