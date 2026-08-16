const std = @import("std");
const testing = std.testing;
const ohsnap = @import("ohsnap");
const vaxis = @import("vaxis");
const editor = @import("../core/editor/editor.zig");
const state = @import("../core/editor/state.zig");
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

test "file screen with rows and filename" {
    const allocator = testing.allocator;
    const io = testing.io;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);
    var test_screen: TestScreen = undefined;
    try test_screen.init(allocator, io);
    defer test_screen.deinit();

    try document.setFilenameAs(allocator, "main.zig");
    try document.appendRow(allocator, "const a = 1;");
    try document.appendRow(allocator, "const b = 2;");
    try document.appendRow(allocator, "pub fn main() void {");
    try document.appendRow(allocator, "}");
    document.cursor_y = 2;
    document.cursor_x = 4;

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
    try oh.snap(@src(),
        \\[]u8
        \\  "const a = 1;                                                                    
        \\const b = 2;                                                                    
        \\pub fn main() void {                                                            
        \\}                                                                               
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
        \\ NORMAL | main.zig - 4 lines | zig                                           3:5
        \\                                                                                "
    ).expectEqual(screen.items);
}

test "command mode shows buffer in command bar" {
    const allocator = testing.allocator;
    const io = testing.io;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);
    var test_screen: TestScreen = undefined;
    try test_screen.init(allocator, io);
    defer test_screen.deinit();

    try document.insertRow(allocator, "hello world", 0);
    document.mode = .COMMAND;
    try editor_state.insertText(allocator, 0, ":w");
    editor_state.command_cursor_x = 2;

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
    try oh.snap(@src(),
        \\[]u8
        \\  "hello world                                                                     
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
        \\ COMMAND | [No File] [+] - 1 lines | text                                    1:1
        \\:w                                                                              "
    ).expectEqual(screen.items);
}

test "search mode shows query and cursor on match" {
    const allocator = testing.allocator;
    const io = testing.io;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);
    var test_screen: TestScreen = undefined;
    try test_screen.init(allocator, io);
    defer test_screen.deinit();

    try document.insertRow(allocator, "hello world", 0);
    try document.insertRow(allocator, "hello again", 1);
    document.mode = .SEARCH;
    try editor_state.insertText(allocator, 0, "/hello");
    editor_state.command_cursor_x = 6;
    document.cursor_y = 1;
    document.cursor_x = 0;

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
    try oh.snap(@src(),
        \\[]u8
        \\  "hello world                                                                     
        \\hello again                                                                     
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
        \\ SEARCH | [No File] [+] - 2 lines | text                                     2:1
        \\/hello                                                                          "
    ).expectEqual(screen.items);
}

test "long file scrolls to keep cursor on screen" {
    const allocator = testing.allocator;
    const io = testing.io;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);
    var test_screen: TestScreen = undefined;
    try test_screen.init(allocator, io);
    defer test_screen.deinit();

    var row_buf: [16]u8 = undefined;
    var row_index: usize = 0;
    while (row_index < 30) : (row_index += 1) {
        const row_text = try std.fmt.bufPrint(&row_buf, "row {d}", .{row_index});
        try document.appendRow(allocator, row_text);
    }
    document.cursor_y = 29;
    document.cursor_x = 0;
    // same values main.zig passes before refresh
    document.scroll(22, 80);

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
    try oh.snap(@src(),
        \\[]u8
        \\  "row 13                                                                          
        \\row 14                                                                          
        \\row 15                                                                          
        \\row 16                                                                          
        \\row 17                                                                          
        \\row 18                                                                          
        \\row 19                                                                          
        \\row 20                                                                          
        \\row 21                                                                          
        \\row 22                                                                          
        \\row 23                                                                          
        \\row 24                                                                          
        \\row 25                                                                          
        \\row 26                                                                          
        \\row 27                                                                          
        \\row 28                                                                          
        \\row 29                                                                          
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\~                                                                               
        \\ NORMAL | [No File] - 30 lines | text                                       30:1
        \\                                                                                "
    ).expectEqual(screen.items);
}
