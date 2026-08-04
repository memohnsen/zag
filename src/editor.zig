const std = @import("std");

pub const Row = struct {
    chars: std.ArrayList(u8) = .empty,

    pub fn deinit(self: *Row, allocator: std.mem.Allocator) void {
        self.chars.deinit(allocator);
    }

    pub fn insertText(
        self: *Row,
        allocator: std.mem.Allocator,
        index: usize,
        text: []const u8,
    ) !void {
        std.debug.assert(index <= self.chars.items.len);
        try self.chars.insertSlice(allocator, index, text);
    }
};

pub const Mode = enum {
    normal,
    insert,
    visual,
    command,
    replace,

    pub fn fmt(self: Mode) []const u8 {
        return switch (self) {
            .normal => "NORMAL",
            .insert => "INSERT",
            .visual => "VISUAL",
            .command => "COMMAND",
            .replace => "REPLACE",
        };
    }
};

pub const Editor = struct {
    rows: std.ArrayList(Row) = .empty,
    cursor_x: usize = 0,
    cursor_y: usize = 0,
    row_offset: usize = 0,
    col_offset: usize = 0,
    filename: ?[]u8 = null,
    mode: Mode = .normal,

    pub fn deinit(self: *Editor, allocator: std.mem.Allocator) void {
        for (self.rows.items) |*row| {
            Row.deinit(row, allocator);
        }
        self.rows.deinit(allocator);

        // Filename is stored separately after duping so must free
        if (self.filename) |name| {
            allocator.free(name);
        }
    }

    pub fn appendRow(self: *Editor, allocator: std.mem.Allocator, input: []const u8) !void {
        var row_list: std.ArrayList(u8) = .empty;
        errdefer row_list.deinit(allocator);
        try row_list.appendSlice(allocator, input);

        const row = Row{ .chars = row_list };
        try self.rows.append(allocator, row);
    }

    pub fn insertText(self: *Editor, allocator: std.mem.Allocator, input: []const u8) !void {
        if (self.rows.items.len == 0) {
            try self.appendRow(allocator, "");
        }

        const row = self.currentRow().?;
        try row.insertText(allocator, self.cursor_x, input);
        self.cursor_x += input.len;
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
    var document = Editor{};
    defer document.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), document.rows.items.len);
    try document.appendRow(allocator, "Hello");
    try std.testing.expectEqual(@as(usize, 1), document.rows.items.len);
    try std.testing.expectEqualStrings("Hello", document.rows.items[0].chars.items);
}

test "inserting rows" {
    var document = Editor{};
    const allocator = std.testing.allocator;
    defer document.deinit(allocator);

    try document.appendRow(allocator, "Hello");
    try document.insertText(allocator, "r");
    const row = document.currentRow().?;

    try std.testing.expectEqualStrings("rHello", row.chars.items);
    try std.testing.expect(document.cursor_x == 1);
}

test "get current row" {
    const allocator = std.testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "zero");
    try document.appendRow(allocator, "one");
    try document.appendRow(allocator, "two");
    document.cursor_y = 2;

    const row = document.currentRow() orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("two", row.chars.items);
}

test "Mode fmt prints string" {
    var document = Editor{};
    document.mode = .normal;
    try std.testing.expect(std.mem.eql(u8, document.mode.fmt(), "NORMAL"));
    document.mode = .insert;
    try std.testing.expect(std.mem.eql(u8, document.mode.fmt(), "INSERT"));
    document.mode = .replace;
    try std.testing.expect(std.mem.eql(u8, document.mode.fmt(), "REPLACE"));
    document.mode = .visual;
    try std.testing.expect(std.mem.eql(u8, document.mode.fmt(), "VISUAL"));
    document.mode = .command;
    try std.testing.expect(std.mem.eql(u8, document.mode.fmt(), "COMMAND"));
}

test "text inserts into row" {
    var document = Editor{};
    const allocator = std.testing.allocator;
    defer document.deinit(allocator);

    try document.appendRow(allocator, "Hello");
    const row = document.currentRow().?;
    try row.insertText(allocator, 0, "r");

    try std.testing.expectEqualStrings(row.chars.items, "rHello");
}
