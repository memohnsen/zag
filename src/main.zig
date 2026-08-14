const std = @import("std");
const log = std.log;

const vaxis = @import("vaxis");
const ui = @import("ui.zig");
const editor = @import("editor/editor.zig");
const commands = @import("commands.zig");
const state = @import("editor/state.zig");
const notifs = @import("editor/notifications.zig");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub fn main(init: std.process.Init) void {
    run(init) catch |err| {
        log.err("Zag failed: {}", .{err});
        std.process.exit(1);
    };
}

fn run(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var document = editor.Editor{};
    defer document.deinit(gpa);

    // Get args and skip the first
    const args = init.minimal.args;
    try handleArgs(args, gpa, io, &document);

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

    var editor_state: state.State = .{};
    defer editor_state.deinit(gpa);

    while (true) {
        const event = try event_loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                // if handle key ever fails it's a keypress error, not worth quitting app for
                // show the error as a notif to the user and break out of the catch
                // this yields false then so we stay in the editor
                const should_quit = commands.handleKey(key, &document, &editor_state, gpa) catch |e| blk: {
                    editor_state.showNotification(&document, gpa, @errorName(e), io) catch {};
                    break :blk false;
                };
                // do nothing if this fails
                // a notif failing is acceptable and logging is worthless in raw mode
                notifs.handleNotifications(&editor_state, &document, gpa, io) catch {};
                if (should_quit) break;
            },
            .winsize => |size| {
                try vx.resize(gpa, tty.writer(), size);
            },
        }

        const window = vx.window();
        const text_height = window.height -| 2;
        document.scroll(text_height, window.width);
        editor_state.hideNotification(&document, io);
        try ui.refresh(&vx, tty.writer(), &document, &editor_state);
        // subtract 2 lines due to command and status bar
        document.rows_shown = vx.window().height - 2;
    }
}

fn handleArgs(
    args: std.process.Args,
    gpa: std.mem.Allocator,
    io: std.Io,
    document: *editor.Editor,
) !void {
    var iter = args.iterateAllocator(gpa) catch |err| {
        log.err("Failed to alloc args: {}", .{err});
        return err;
    };
    defer iter.deinit();
    _ = iter.skip();

    if (iter.next()) |filename| {
        const cwd = std.Io.Dir.cwd();
        const file = cwd.openFile(io, filename, .{}) catch |err| {
            log.err("Failed to load file '{s}': {}", .{
                filename,
                err,
            });
            return err;
        };
        defer file.close(io);

        // Must duplicate this since the iter owns the original filename
        const stored_filename = gpa.dupe(u8, filename) catch |err| {
            log.err("Failed to duplicate file name: {}", .{err});
            return err;
        };
        document.filename = stored_filename;

        // Create a buffer to store contents, alloc the remaining, then append to view
        var buf: [4096]u8 = undefined;
        var reader = file.reader(io, &buf);
        const contents = reader.interface.allocRemaining(gpa, .limited(10 * 1024 * 1024)) catch |err| {
            log.err("Failed to alloc remaining space for contents: {}", .{err});
            return err;
        };
        defer gpa.free(contents);

        var rows = std.mem.splitScalar(u8, contents, '\n');

        while (rows.next()) |row| {
            const trimmed = std.mem.trimEnd(u8, row, "\r");
            document.appendRow(gpa, trimmed) catch |err| {
                log.err("Failed to append file rows: {}", .{err});
                return err;
            };
        }
    }
}

test "all" {
    _ = @import("commands.zig");
    _ = @import("editor/editor.zig");
    _ = @import("ui.zig");
    _ = @import("editor/row.zig");
    _ = @import("editor/state.zig");
    _ = @import("editor/notifications.zig");
}
