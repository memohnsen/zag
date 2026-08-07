const std = @import("std");
const mem = std.mem;
const testing = std.testing;

pub const Row = struct {
    // the actual text in each row of the file
    chars: std.ArrayList(u8) = .empty,

    pub fn deinit(self: *Row, allocator: mem.Allocator) void {
        self.chars.deinit(allocator);
    }

    pub fn insertText(
        self: *Row,
        allocator: mem.Allocator,
        index: usize,
        text: []const u8,
    ) !void {
        std.debug.assert(index <= self.chars.items.len);
        try self.chars.insertSlice(allocator, index, text);
    }

    pub fn removeByte(self: *Row, index: usize) void {
        std.debug.assert(index < self.chars.items.len);
        _ = self.chars.orderedRemove(index);
    }
};

test "byte is removed from line" {
    var row = Row{};
    const allocator = testing.allocator;
    defer row.deinit(allocator);

    try row.insertText(allocator, 0, "Hello");
    row.removeByte(2);
    try testing.expectEqualStrings("Helo", row.chars.items);
}

test "text inserts into row" {
    var row = Row{};
    const allocator = testing.allocator;
    defer row.deinit(allocator);

    try row.insertText(allocator, 0, "Hello");
    try row.insertText(allocator, 0, "r");

    try testing.expectEqualStrings("rHello", row.chars.items);
}
