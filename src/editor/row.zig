const std = @import("std");
const mem = std.mem;
const testing = std.testing;

pub const Row = struct {
    // the actual text in each row of the file
    chars: std.ArrayList(u8) = .empty,
    render: std.ArrayList(u8) = .empty,

    pub fn deinit(self: *Row, allocator: mem.Allocator) void {
        self.chars.deinit(allocator);
        self.render.deinit(allocator);
    }

    pub fn init(allocator: mem.Allocator, input: []const u8) !Row {
        var row = Row{ .chars = .empty, .render = .empty };
        errdefer row.deinit(allocator);

        try row.insertText(allocator, 0, input);
        return row;
    }

    pub fn insertText(
        self: *Row,
        allocator: mem.Allocator,
        index: usize,
        text: []const u8,
    ) !void {
        std.debug.assert(index <= self.chars.items.len);
        try self.chars.insertSlice(allocator, index, text);
        try self.updateRender(allocator);
    }

    pub fn removeByte(self: *Row, index: usize, allocator: mem.Allocator) !void {
        std.debug.assert(index < self.chars.items.len);
        _ = self.chars.orderedRemove(index);
        try self.updateRender(allocator);
    }

    pub fn updateRender(self: *Row, allocator: mem.Allocator) !void {
        self.render.clearRetainingCapacity();
        for (self.chars.items) |char| {
            if (char == '\t') {
                const tab_width = 4 - (self.render.items.len % 4);
                try self.render.appendNTimes(allocator, ' ', tab_width);
            } else {
                try self.render.append(allocator, char);
            }
        }
    }

    pub fn cursorXtoRenderX(self: *const Row, cursor_x: usize) usize {
        var renderX: usize = 0;
        for (self.chars.items[0..cursor_x]) |char| {
            if (char == '\t') {
                const tab_width = 4 - (renderX % 4);
                renderX += tab_width;
            } else {
                renderX += 1;
            }
        }
        return renderX;
    }
};

// -------------------------------------------------------
// -------------------------------------------------------
// TESTS
// -------------------------------------------------------
// -------------------------------------------------------

test "byte is removed from line" {
    var row = Row{};
    const allocator = testing.allocator;
    defer row.deinit(allocator);

    try row.insertText(allocator, 0, "Hello");
    try row.removeByte(2, allocator);
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

test "\t shows as 4 spaces" {
    var row = Row{};
    const allocator = testing.allocator;
    defer row.deinit(allocator);

    try row.insertText(allocator, 0, "\th");
    try testing.expectEqualStrings("    h", row.render.items);

    var new_row = Row{};
    defer new_row.deinit(allocator);
    try new_row.insertText(allocator, 0, "\t\th");
    try testing.expectEqualStrings("\t\th", new_row.chars.items);
    try testing.expectEqualStrings("        h", new_row.render.items);
}

test "\t within word renders" {
    var row = Row{};
    const allocator = testing.allocator;
    defer row.deinit(allocator);

    try row.insertText(allocator, 0, "a\th");
    try testing.expectEqualStrings("a   h", row.render.items);
    try testing.expectEqualStrings("a\th", row.chars.items);
}

test "cursor x to render x" {
    var row = Row{};
    const allocator = testing.allocator;
    defer row.deinit(allocator);

    try row.insertText(allocator, 0, "a\th");
    try testing.expectEqual(0, row.cursorXtoRenderX(0));
    try testing.expectEqual(1, row.cursorXtoRenderX(1));
    try testing.expectEqual(4, row.cursorXtoRenderX(2));
    try testing.expectEqual(5, row.cursorXtoRenderX(3));
}
