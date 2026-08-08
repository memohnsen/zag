const std = @import("std");

pub const Row = struct {
    chars: []u8,

    pub fn deinit(self: *Row, allocator: std.mem.Allocator) void {
        allocator.free(self.chars);
    }
};

pub const Editor = struct {
    rows: std.ArrayList(Row) = .empty,
    cursor_x: usize = 0,
    cursor_y: usize = 0,
    row_offset: usize = 0,
    col_offset: usize = 0,

    pub fn deinit(self: *Editor, allocator: std.mem.Allocator) void {
        for (self.rows.items) |*row| {
            Row.deinit(row, allocator);
        }
        self.rows.deinit(allocator);
    }

    pub fn appendRow(self: *Editor, allocator: std.mem.Allocator, input: []const u8) !void {
        const chars = try allocator.dupe(u8, input);
        errdefer allocator.free(chars);

        const row = Row{ .chars = chars };
        try self.rows.append(allocator, row);
    }

    pub fn currentRow(self: *Editor) ?*Row {
        if (self.cursor_y >= self.rows.items.len) {
            return null;
        } else {
            return &self.rows.items[self.cursor_y];
        }
    }

    pub fn scroll(self: *Editor, screen_rows: usize, screen_cols: usize) void {
        if (screen_rows == 0 or screen_cols == 0) return;

        if (self.cursor_y < self.row_offset) {
            self.row_offset = self.cursor_y;
        } else if (self.cursor_y - self.row_offset >= screen_rows) {
            self.row_offset = self.cursor_y - screen_rows + 1;
        }

        if (self.cursor_x < self.col_offset) {
            self.col_offset = self.cursor_x;
        } else if (self.cursor_x - self.col_offset >= screen_cols) {
            self.col_offset = self.cursor_x - screen_cols + 1;
        }
    }
};

test "appending rows" {
    const allocator = std.testing.allocator;
    var ed: Editor = .{};
    defer ed.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), ed.rows.items.len);
    try ed.appendRow(allocator, "Hello");
    try std.testing.expectEqual(@as(usize, 1), ed.rows.items.len);
    try std.testing.expectEqualStrings("Hello", ed.rows.items[0].chars);
}

test "get current row" {
    const allocator = std.testing.allocator;
    var ed: Editor = .{};
    defer ed.deinit(allocator);

    try ed.appendRow(allocator, "zero");
    try ed.appendRow(allocator, "one");
    try ed.appendRow(allocator, "two");
    ed.cursor_y = 2;

    const row = ed.currentRow() orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("two", row.chars);
}