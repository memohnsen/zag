const std = @import("std");
const mem = std.mem;
const testing = std.testing;

pub const Row = struct {
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

pub const Mode = enum {
    NORMAL,
    INSERT,
    VISUAL,
    COMMAND,
    REPLACE,
};

pub const Editor = struct {
    rows: std.ArrayList(Row) = .empty,
    rows_shown: usize = 0,
    cursor_x: usize = 0,
    cursor_y: usize = 0,
    row_offset: usize = 0,
    col_offset: usize = 0,
    filename: ?[]u8 = null,
    mode: Mode = .NORMAL,

    pub fn deinit(self: *Editor, allocator: mem.Allocator) void {
        for (self.rows.items) |*row| {
            Row.deinit(row, allocator);
        }
        self.rows.deinit(allocator);

        // Filename is stored separately after duping so must free
        if (self.filename) |name| {
            allocator.free(name);
        }
    }

    pub fn appendRow(self: *Editor, allocator: mem.Allocator, input: []const u8) !void {
        var row_list: std.ArrayList(u8) = .empty;
        errdefer row_list.deinit(allocator);
        try row_list.appendSlice(allocator, input);

        const row = Row{ .chars = row_list };
        try self.rows.append(allocator, row);
    }

    pub fn insertRow(
        self: *Editor,
        allocator: mem.Allocator,
        input: []const u8,
        index: usize,
    ) !void {
        var row_list: std.ArrayList(u8) = .empty;
        errdefer row_list.deinit(allocator);
        try row_list.appendSlice(allocator, input);

        const row = Row{ .chars = row_list };
        try self.rows.insert(allocator, index, row);
    }

    pub fn insertNewLine(
        self: *Editor,
        allocator: mem.Allocator,
    ) !void {
        const y = self.cursor_y;
        const x = self.cursor_x;

        const remaining_row_chars = self.rows.items[y].chars.items[x..];
        try self.insertRow(allocator, remaining_row_chars, y + 1);

        const og_row = &self.rows.items[y];
        og_row.chars.shrinkRetainingCapacity(x);
        self.cursor_y = y + 1;
        self.cursor_x = 0;
    }

    pub fn insertNewLineBlank(
        self: *Editor,
        allocator: mem.Allocator,
    ) !void {
        try self.insertRow(allocator, "", self.cursor_y + 1);

        self.cursor_y += 1;
        self.cursor_x = 0;
    }

    pub fn insertText(self: *Editor, allocator: mem.Allocator, input: []const u8) !void {
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
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), document.rows.items.len);
    try document.appendRow(allocator, "Hello");
    try testing.expectEqual(@as(usize, 1), document.rows.items.len);
    try testing.expectEqualStrings("Hello", document.rows.items[0].chars.items);
}

test "inserting rows" {
    var document = Editor{};
    const allocator = testing.allocator;
    defer document.deinit(allocator);

    try document.appendRow(allocator, "Hello");
    try document.insertText(allocator, "r");
    const row = document.currentRow().?;

    try testing.expectEqualStrings("rHello", row.chars.items);
    try testing.expect(document.cursor_x == 1);
}

test "get current row" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "zero");
    try document.appendRow(allocator, "one");
    try document.appendRow(allocator, "two");
    document.cursor_y = 2;

    const row = document.currentRow() orelse return error.TestExpectedEqual;
    try testing.expectEqualStrings("two", row.chars.items);
}

test "text inserts into row" {
    var document = Editor{};
    const allocator = testing.allocator;
    defer document.deinit(allocator);

    try document.appendRow(allocator, "Hello");
    const row = document.currentRow().?;
    try row.insertText(allocator, 0, "r");

    try testing.expectEqualStrings("rHello", row.chars.items);
}

test "byte is removed from line" {
    var document = Editor{};
    const allocator = testing.allocator;
    defer document.deinit(allocator);

    try document.appendRow(allocator, "Hello");
    const row = document.currentRow().?;
    document.cursor_x = 3;
    row.removeByte(document.cursor_x - 1);
    try testing.expectEqualStrings("Helo", row.chars.items);
}

test "inserting new row" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "zero");
    try document.appendRow(allocator, "two");

    try document.insertRow(allocator, "one", 1);
    try testing.expectEqualStrings("zero", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("one", document.rows.items[1].chars.items);
    try testing.expectEqualStrings("two", document.rows.items[2].chars.items);
}

test "inserting new line" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "hello world");
    document.cursor_x = 5;

    try document.insertNewLine(allocator);
    try testing.expectEqualStrings("hello", document.rows.items[0].chars.items);
    try testing.expectEqualStrings(" world", document.rows.items[1].chars.items);
    try testing.expect(document.cursor_y == 1);
    try testing.expect(document.cursor_x == 0);
}
