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
};
