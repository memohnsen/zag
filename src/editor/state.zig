const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const editor = @import("editor.zig");

pub const State = struct {
    command_buffer: std.ArrayList(u8) = .empty,
    command_cursor_x: usize = 0,

    // pending chars for multichar motions like gg, gl, gh, dd
    pending_g: bool = false,
    pending_d: bool = false,

    replace_mult: bool = false,

    save_requested: bool = false,
    notif_started: ?std.Io.Timestamp = null,

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        self.command_buffer.deinit(allocator);
    }

    pub fn insertText(
        self: *State,
        allocator: mem.Allocator,
        index: usize,
        text: []const u8,
    ) !void {
        std.debug.assert(index <= self.command_buffer.items.len);
        try self.command_buffer.insertSlice(allocator, index, text);
    }

    pub fn removeByte(self: *State, index: usize) void {
        std.debug.assert(index < self.command_buffer.items.len);
        _ = self.command_buffer.orderedRemove(index);
    }

    pub fn clearText(self: *State, document: *editor.Editor) void {
        self.command_buffer.clearRetainingCapacity();
        self.notif_started = null;
        self.command_cursor_x = 0;
        document.mode = .NORMAL;
    }

    pub fn showNotification(
        self: *State,
        document: *editor.Editor,
        allocator: mem.Allocator,
        text: []const u8,
        io: std.Io,
    ) !void {
        self.clearText(document);
        try self.command_buffer.insertSlice(allocator, 0, text);
        self.notif_started = std.Io.Timestamp.now(io, .awake);
    }

    pub fn hideNotification(self: *State, document: *editor.Editor, io: std.Io) void {
        const started = self.notif_started orelse return;
        const now = std.Io.Timestamp.now(io, .awake);
        const elapsed = started.durationTo(now);

        if (elapsed.toSeconds() >= 3) {
            self.clearText(document);
            self.notif_started = null;
        }
    }
};

test "text inserts into command bar" {
    var state = State{};
    const allocator = testing.allocator;
    defer state.deinit(allocator);

    try state.insertText(allocator, 0, "Hello");

    try testing.expectEqualStrings("Hello", state.command_buffer.items);
}

test "byte is removed from line" {
    var state = State{};
    const allocator = testing.allocator;
    defer state.deinit(allocator);

    try state.insertText(allocator, 0, "Hello");
    state.removeByte(2);
    try testing.expectEqualStrings("Helo", state.command_buffer.items);
}

test "notifications show in command line" {
    const allocator = testing.allocator;
    const io = testing.io;
    var editor_state = State{};
    defer editor_state.deinit(allocator);
    var document = editor.Editor{};
    defer document.deinit(allocator);

    try editor_state.showNotification(&document, allocator, "File saved", io);
    try testing.expectEqualStrings("File saved", editor_state.command_buffer.items);
}

test "notifications hide after 3s" {
    const allocator = testing.allocator;
    const io = testing.io;
    var editor_state = State{};
    defer editor_state.deinit(allocator);
    var document = editor.Editor{};
    defer document.deinit(allocator);

    try editor_state.showNotification(&document, allocator, "File saved", io);
    try testing.expectEqualStrings("File saved", editor_state.command_buffer.items);

    const now = std.Io.Timestamp.now(io, .awake);
    editor_state.notif_started = now.subDuration(std.Io.Duration.fromSeconds(4));
    editor_state.hideNotification(&document, io);

    try testing.expect(editor_state.command_cursor_x == 0);
    try testing.expect(document.mode == .NORMAL);
    try testing.expect(editor_state.command_buffer.items.len == 0);
}
