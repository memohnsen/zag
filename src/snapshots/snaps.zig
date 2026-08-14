const std = @import("std");
const testing = std.testing;
const ohsnap = @import("ohsnap");
const vaxis = @import("vaxis");
const editor = @import("../editor/editor.zig");
const state = @import("../editor/state.zig");
const ui = @import("../ui.zig");

const TestScreen = struct {
    allocator: std.mem.Allocator,
    env_map: std.process.Environ.Map,
    output_buffer: [16384]u8,
    output: std.Io.Writer,
    ui_buffers: ui.Buffers,
    vx: vaxis.Vaxis,

    fn init(self: *TestScreen, allocator: std.mem.Allocator, io: std.Io) !void {
        self.allocator = allocator;
        self.env_map = std.process.Environ.Map.init(allocator);
        errdefer self.env_map.deinit();
        self.output = std.Io.Writer.fixed(&self.output_buffer);
        self.ui_buffers = .{};
        self.vx = try vaxis.init(io, allocator, &self.env_map, .{});
        errdefer self.vx.deinit(allocator, &self.output);
        try self.vx.resize(allocator, &self.output, .{
            .cols = 80,
            .rows = 24,
            .x_pixel = 0,
            .y_pixel = 0,
        });
    }

    fn deinit(self: *TestScreen) void {
        self.vx.deinit(self.allocator, &self.output);
        self.env_map.deinit();
    }
};

fn readRows(
    screen: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    vx: *vaxis.Vaxis,
    width: usize,
    height: usize,
) !void {
    for (0..height) |row| {
        if (row != 0) try screen.append(allocator, '\n');

        for (0..width) |col| {
            const cell = vx.screen.readCell(@intCast(col), @intCast(row)).?;
            try screen.appendSlice(allocator, cell.char.grapheme);
        }
    }
}

test "base welcome screen" {
    const allocator = testing.allocator;
    const io = testing.io;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);
    var test_screen: TestScreen = undefined;
    try test_screen.init(allocator, io);
    defer test_screen.deinit();

    try ui.refresh(
        &test_screen.vx,
        &test_screen.output,
        &document,
        &editor_state,
        &test_screen.ui_buffers,
    );

    var screen: std.ArrayList(u8) = .empty;
    defer screen.deinit(allocator);
    try readRows(&screen, allocator, &test_screen.vx, 80, 24);

    const oh = ohsnap.OhSnap(ohsnap.default_pretty_options);
    try oh.snap(
        @src(),
        \\[]u8
        \\  "~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                         Zag Editor -- Version 0.1.0                           
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\ NORMAL | [No File] - 0 lines | text                                         1:1
        \\                                                                                "
        ,
    ).expectEqual(screen.items);
}

test "welcome screen in insert mode with text" {
    const allocator = testing.allocator;
    const io = testing.io;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);
    var test_screen: TestScreen = undefined;
    try test_screen.init(allocator, io);
    defer test_screen.deinit();

    try document.insertRow(allocator, "typing ", 0);
    document.mode = .INSERT;
    document.cursor_x = 6;

    try ui.refresh(
        &test_screen.vx,
        &test_screen.output,
        &document,
        &editor_state,
        &test_screen.ui_buffers,
    );

    var screen: std.ArrayList(u8) = .empty;
    defer screen.deinit(allocator);
    try readRows(&screen, allocator, &test_screen.vx, 80, 24);

    const oh = ohsnap.OhSnap(ohsnap.default_pretty_options);
    try oh.snap(
        @src(),
        \\[]u8
        \\  "typing                                                                          
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\ INSERT | [No File] [+] - 1 lines | text                                     1:7
        \\                                                                                "
        ,
    ).expectEqual(screen.items);
}
