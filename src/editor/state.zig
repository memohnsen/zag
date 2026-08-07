const std = @import("std");
const testing = std.testing;
const mem = std.mem;

pub const State = struct {
    command_buffer: std.ArrayList(u8) = .empty,
    command_cursor_x: usize = 0,

    // pending chars for multichar motions like gg, gl, gh, dd
    pending_g: bool = false,
    pending_d: bool = false,

    // save request is sent to main where saving happens
    save_requested: bool = false,

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

    pub fn clearText(self: *State) void {
        self.command_buffer.clearRetainingCapacity();
        self.command_cursor_x = 0;
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
