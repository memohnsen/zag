const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Row = @import("row.zig").Row;
const state = @import("state.zig");

pub const Mode = enum {
    NORMAL,
    INSERT,
    VISUAL,
    COMMAND,
    REPLACE,
    SEARCH,
};

pub const SearchDirection = enum {
    forward,
    backward,
};

pub const Editor = struct {
    // the total rows of the file
    rows: std.ArrayList(Row) = .empty,
    // the current rows shown on the terminal
    rows_shown: usize = 0,
    cursor_x: usize = 0,
    cursor_y: usize = 0,
    render_x: usize = 0,
    // which row is currently the top row shown on the screen
    row_offset: usize = 0,
    // which col is currently the leftmost shown on the screen
    col_offset: usize = 0,
    filename: ?[]u8 = null,
    mode: Mode = .NORMAL,
    // NOTE: this is a poor way to do it, change it once we add an undo history later
    // ideally we compare against a snapshot of the file
    unsaved_edits: bool = false,

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
        var row = try Row.init(allocator, input);
        errdefer row.deinit(allocator);
        try self.rows.append(allocator, row);
    }

    pub fn removeRow(self: *Editor, allocator: mem.Allocator, index: usize) !void {
        if (index < self.rows.items.len) {
            var row = self.rows.orderedRemove(index);
            row.deinit(allocator);
        }
        self.unsaved_edits = true;
    }

    pub fn joinWithPrevRow(self: *Editor, allocator: mem.Allocator) !void {
        if (self.cursor_y == 0) {
            return;
        }

        if (self.currentRow()) |row| {
            const prev_row = &self.rows.items[self.cursor_y - 1];
            const prev_row_length = self.rows.items[self.cursor_y - 1].chars.items.len;
            const current_row_text = row.chars.items;
            try prev_row.insertText(allocator, prev_row_length, current_row_text);
            try self.removeRow(allocator, self.cursor_y);
            self.cursor_x = prev_row_length;
            self.cursor_y = self.cursor_y -| 1;
        }
    }

    pub fn joinWithNextRow(self: *Editor, allocator: mem.Allocator) !void {
        if (self.cursor_y + 1 == self.rows.items.len) {
            return;
        }

        if (self.currentRow()) |row| {
            const next_row_text = self.rows.items[self.cursor_y + 1].chars.items;
            const current_row_len = row.chars.items.len;
            try row.insertText(allocator, current_row_len, next_row_text);
            try self.removeRow(allocator, self.cursor_y + 1);
            self.cursor_x = current_row_len;
        }
    }

    pub fn deleteRemainingLine(self: *Editor, allocator: mem.Allocator) !void {
        const y = self.cursor_y;
        const x = self.cursor_x;

        if (self.rows.items.len == 0) {
            return;
        }

        const og_row = &self.rows.items[y];
        og_row.chars.shrinkRetainingCapacity(x);
        try og_row.updateRender(allocator);
        self.unsaved_edits = true;
    }

    pub fn insertRow(
        self: *Editor,
        allocator: mem.Allocator,
        input: []const u8,
        index: usize,
    ) !void {
        var row = try Row.init(allocator, input);
        errdefer row.deinit(allocator);
        try self.rows.insert(allocator, index, row);
        self.unsaved_edits = true;
    }

    pub fn insertNewLine(
        self: *Editor,
        allocator: mem.Allocator,
    ) !void {
        const y = self.cursor_y;
        const x = self.cursor_x;

        if (self.rows.items.len == 0) {
            try self.insertRow(allocator, "", self.cursor_y);
        }

        const remaining_row_chars = self.rows.items[y].chars.items[x..];
        try self.insertRow(allocator, remaining_row_chars, y + 1);

        const og_row = &self.rows.items[y];
        og_row.chars.shrinkRetainingCapacity(x);
        try og_row.updateRender(allocator);
        self.cursor_y = y + 1;
        self.cursor_x = 0;
    }

    pub fn insertText(self: *Editor, allocator: mem.Allocator, input: []const u8) !void {
        if (input.len == 0) {
            return;
        }

        if (self.rows.items.len == 0) {
            try self.appendRow(allocator, "");
        }

        const row = self.currentRow().?;
        try row.insertText(allocator, self.cursor_x, input);
        self.unsaved_edits = true;
        self.cursor_x += input.len;
    }

    pub fn replaceChar(
        self: *Editor,
        allocator: mem.Allocator,
        input: []const u8,
        index: usize,
    ) !void {
        const row = self.currentRow() orelse return;
        if (index >= row.chars.items.len) {
            return;
        }

        try self.rows.items[self.cursor_y].removeByte(index, allocator);
        try self.rows.items[self.cursor_y].insertText(allocator, index, input);
        self.unsaved_edits = true;
    }

    pub fn currentRow(self: *Editor) ?*Row {
        if (self.cursor_y >= self.rows.items.len) {
            return null;
        } else {
            return &self.rows.items[self.cursor_y];
        }
    }

    pub fn scroll(self: *Editor, screen_rows: usize, screen_cols: usize) void {
        self.render_x = 0;
        if (self.currentRow()) |row| {
            self.render_x = row.cursorXtoRenderX(self.cursor_x);
        }
        if (screen_rows == 0 or screen_cols == 0) return;

        // vertical
        if (self.cursor_y < self.row_offset) {
            self.row_offset = self.cursor_y;
        } else if (self.cursor_y - self.row_offset >= screen_rows) {
            self.row_offset = self.cursor_y - screen_rows + 1;
        }

        // horizontal
        if (self.render_x < self.col_offset) {
            self.col_offset = self.render_x;
        } else if (self.render_x - self.col_offset >= screen_cols) {
            self.col_offset = self.render_x - screen_cols + 1;
        }
    }

    pub fn toOwnedText(self: *const Editor, allocator: mem.Allocator) ![]u8 {
        var list: std.ArrayList(u8) = .empty;
        errdefer list.deinit(allocator);

        for (self.rows.items, 0..) |row, index| {
            if (index != 0) {
                try list.append(allocator, '\n');
            }
            try list.appendSlice(allocator, row.chars.items);
        }

        return try list.toOwnedSlice(allocator);
    }

    pub fn saveFile(
        self: *Editor,
        allocator: mem.Allocator,
        io: std.Io,
        dir: std.Io.Dir,
    ) !void {
        if (self.filename) |filename| {
            const text = try self.toOwnedText(allocator);
            defer allocator.free(text);

            try dir.writeFile(io, .{ .sub_path = filename, .data = text });
            self.unsaved_edits = false;
        }
    }

    pub fn setFilenameAs(
        self: *Editor,
        allocator: mem.Allocator,
        filename: []const u8,
    ) !void {
        const name = try allocator.dupe(u8, filename);
        if (self.filename) |file| {
            allocator.free(file);
        }
        self.filename = name;
    }

    // Searching forward starts at the start row and col looping to the end of the file
    // Then it jumps to the start of the file to the current line
    // Then finally we must go back to start line and check chars to where the cursor started
    //
    // Searching backward is the same we just start with start line check first
    pub fn search(
        self: *Editor,
        query: []const u8,
        start_row: usize,
        start_col: usize,
        direction: SearchDirection,
    ) bool {
        if (query.len == 0 or start_row >= self.rows.items.len) {
            return false;
        }

        switch (direction) {
            .forward => {
                for (self.rows.items[start_row..], start_row..) |row, row_index| {
                    var slice_start: usize = 0;
                    if (row_index == start_row) {
                        slice_start = @min(start_col, row.chars.items.len);
                    }

                    if (mem.indexOf(u8, row.chars.items[slice_start..], query)) |col_index| {
                        self.cursor_y = row_index;
                        self.cursor_x = col_index + slice_start;
                        return true;
                    }
                }

                for (self.rows.items[0..start_row], 0..start_row) |row, row_index| {
                    if (mem.indexOf(u8, row.chars.items, query)) |col_index| {
                        self.cursor_y = row_index;
                        self.cursor_x = col_index;
                        return true;
                    }
                }

                const chars = self.rows.items[start_row].chars.items;
                const col = @min(start_col, chars.len);

                if (mem.indexOf(u8, chars, query)) |col_index| {
                    if (col_index < col) {
                        self.cursor_y = start_row;
                        self.cursor_x = col_index;
                        return true;
                    }
                }
            },
            .backward => {
                const chars = self.rows.items[start_row].chars.items;
                const col = @min(start_col, chars.len);

                if (mem.lastIndexOf(u8, chars[0..col], query)) |col_index| {
                    if (col_index < col) {
                        self.cursor_y = start_row;
                        self.cursor_x = col_index;
                        return true;
                    }
                }

                var row_index = start_row;
                while (row_index > 0) {
                    row_index -= 1;
                    if (mem.lastIndexOf(u8, self.rows.items[row_index].chars.items, query)) |col_index| {
                        self.cursor_y = row_index;
                        self.cursor_x = col_index;
                        return true;
                    }
                }

                var row_index_from_bottom = self.rows.items.len;
                while (row_index_from_bottom > start_row + 1) {
                    row_index_from_bottom -= 1;
                    if (mem.lastIndexOf(u8, self.rows.items[row_index_from_bottom].chars.items, query)) |col_index| {
                        self.cursor_y = row_index_from_bottom;
                        self.cursor_x = col_index;
                        return true;
                    }
                }

                if (mem.lastIndexOf(u8, chars, query)) |col_index| {
                    if (col_index >= col) {
                        self.cursor_y = start_row;
                        self.cursor_x = col_index;
                        return true;
                    }
                }
            },
        }
        return false;
    }
};

// -------------------------------------------------------
// -------------------------------------------------------
// TESTS
// -------------------------------------------------------
// -------------------------------------------------------

// INSERTING TEXT
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

    try document.appendRow(allocator, "hello\tworld");
    document.cursor_x = 5;

    try document.insertNewLine(allocator);
    try testing.expectEqualStrings("hello", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("\tworld", document.rows.items[1].chars.items);
    try testing.expectEqualStrings("hello", document.rows.items[0].render.items);
    try testing.expectEqualStrings("    world", document.rows.items[1].render.items);
    try testing.expect(document.cursor_y == 1);
    try testing.expect(document.cursor_x == 0);
}

test "inserting new line on empty file" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.insertNewLine(allocator);
    try testing.expect(document.rows.items.len == 2);
    try testing.expect(document.cursor_y == 1);
    try testing.expect(document.cursor_x == 0);
}

// DELETING TEXT
test "removing line" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "world");
    document.cursor_y = 1;

    try testing.expect(document.rows.items.len == 2);
    try document.removeRow(allocator, document.cursor_y);
    try testing.expect(document.rows.items.len == 1);
    try testing.expectEqualStrings("hello", document.rows.items[0].chars.items);
}

test "removing line on empty row" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "");
    try document.appendRow(allocator, "world");
    document.cursor_y = 1;

    try testing.expect(document.rows.items.len == 3);
    try document.removeRow(allocator, document.cursor_y);
    try testing.expect(document.rows.items.len == 2);
    try testing.expectEqualStrings("hello", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("world", document.rows.items[1].chars.items);
}

test "removing line does nothing on empty file" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.removeRow(allocator, document.cursor_y);
    try testing.expect(document.rows.items.len == 0);
}

test "removing remainder of line" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "hello");
    document.cursor_x = 1;

    try document.deleteRemainingLine(allocator);
    try testing.expectEqualStrings("h", document.rows.items[0].chars.items);
    try testing.expectEqualStrings("h", document.rows.items[0].render.items);
}

// JOINING TEXT
test "join row with prev row" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, " world");
    document.cursor_y = 1;
    document.cursor_x = 0;

    try document.joinWithPrevRow(allocator);
    try testing.expect(document.rows.items.len == 1);
    try testing.expectEqualStrings("hello world", document.rows.items[0].chars.items);
}

test "join row with prev empty row" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, " world");
    document.cursor_y = 0;
    document.cursor_x = 0;

    try document.joinWithPrevRow(allocator);
    try testing.expect(document.rows.items.len == 1);
    try testing.expectEqualStrings(" world", document.rows.items[0].chars.items);
}

test "join row with next row" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, " world");
    document.cursor_y = 0;
    document.cursor_x = 0;

    try document.joinWithNextRow(allocator);
    try testing.expect(document.rows.items.len == 1);
    try testing.expectEqualStrings("hello world", document.rows.items[0].chars.items);
}

test "join row with next empty row" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, " world");
    document.cursor_y = 1;
    document.cursor_x = 0;

    try document.joinWithNextRow(allocator);
    try testing.expect(document.rows.items.len == 2);
    try testing.expectEqualStrings(" world", document.rows.items[1].chars.items);
}

// SAVING
test "saving file with text" {
    const allocator = testing.allocator;
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var document = Editor{};
    defer document.deinit(allocator);

    document.filename = try allocator.dupe(u8, "test.txt");
    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "world");

    try document.saveFile(allocator, io, tmp.dir);

    const saved = try tmp.dir.readFileAlloc(io, "test.txt", allocator, .limited(1024));
    defer allocator.free(saved);

    try testing.expectEqualStrings("hello\nworld", saved);
}

test "saving file overwrites old data" {
    const allocator = testing.allocator;
    const io = testing.io;
    var document = Editor{};
    defer document.deinit(allocator);

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const file = try tmp.dir.createFile(io, "test.txt", .{});
    defer file.close(io);
    try file.writeStreamingAll(io, "hello\nworld");

    document.filename = try allocator.dupe(u8, "test.txt");
    try document.appendRow(allocator, "new contents");

    try document.saveFile(allocator, io, tmp.dir);

    const saved = try tmp.dir.readFileAlloc(io, "test.txt", allocator, .limited(1024));
    defer allocator.free(saved);

    try testing.expectEqualStrings("new contents", saved);
}

test "save file with new file name" {
    const allocator = testing.allocator;
    const io = testing.io;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.setFilenameAs(allocator, "new.txt");

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const file = try tmp.dir.createFile(io, document.filename.?, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, "hello\nworld");

    try document.appendRow(allocator, "new contents");

    try document.saveFile(allocator, io, tmp.dir);

    const saved = try tmp.dir.readFileAlloc(io, document.filename.?, allocator, .limited(1024));
    defer allocator.free(saved);

    try testing.expectEqualStrings("new contents", saved);
}

// REPLACING TEXT
test "replacing char works on text" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "new contents");
    document.cursor_x = 2;
    try document.replaceChar(allocator, "e", document.cursor_x);
    try testing.expectEqualStrings("nee contents", document.rows.items[0].chars.items);
}

test "replacing char does nothing on empty row" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "");
    try document.replaceChar(allocator, "e", document.cursor_x);
    try testing.expectEqual(1, document.rows.items.len);
    try testing.expectEqualStrings("", document.rows.items[0].chars.items);
}

test "replacing char does nothing on empty file" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.replaceChar(allocator, "e", document.cursor_x);
    try testing.expectEqual(0, document.rows.items.len);
}

test "changing text shows unsaved_edits true" {
    const allocator = testing.allocator;
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var document = Editor{};
    defer document.deinit(allocator);

    document.filename = try allocator.dupe(u8, "test.txt");
    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "world");

    try document.saveFile(allocator, io, tmp.dir);
    try testing.expect(!document.unsaved_edits);
    try document.replaceChar(allocator, "e", document.cursor_x);
    try testing.expect(document.unsaved_edits);

    try document.saveFile(allocator, io, tmp.dir);
    try testing.expect(!document.unsaved_edits);
    try document.insertNewLine(allocator);
    try testing.expect(document.unsaved_edits);

    try document.saveFile(allocator, io, tmp.dir);
    try testing.expect(!document.unsaved_edits);
    try document.insertRow(allocator, "e", 0);
    try testing.expect(document.unsaved_edits);

    try document.saveFile(allocator, io, tmp.dir);
    try testing.expect(!document.unsaved_edits);
    try document.insertText(allocator, "e");
    try testing.expect(document.unsaved_edits);

    try document.saveFile(allocator, io, tmp.dir);
    try testing.expect(!document.unsaved_edits);
    try document.removeRow(allocator, 1);
    try testing.expect(document.unsaved_edits);

    try document.saveFile(allocator, io, tmp.dir);
    try testing.expect(!document.unsaved_edits);
    try document.joinWithNextRow(allocator);
    try testing.expect(document.unsaved_edits);

    try document.saveFile(allocator, io, tmp.dir);
    try testing.expect(!document.unsaved_edits);
    try document.joinWithPrevRow(allocator);
    try testing.expect(document.unsaved_edits);
}

// SEARCHING
test "searching finds the string" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "hello there world");
    try document.appendRow(allocator, "this is a new line");
    try testing.expect(document.search("there", 0, 0, .forward));
    try testing.expectEqual(6, document.cursor_x);
    try testing.expectEqual(0, document.cursor_y);

    try testing.expect(document.search("new", 0, 0, .forward));
    try testing.expectEqual(10, document.cursor_x);
    try testing.expectEqual(1, document.cursor_y);

    try testing.expect(!document.search("none", 0, 0, .forward));
    try testing.expectEqual(10, document.cursor_x);
    try testing.expectEqual(1, document.cursor_y);
}

test "searching forward" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);

    try document.appendRow(allocator, "hello there world");
    try document.appendRow(allocator, "hello there world");
    try testing.expect(document.search("there", document.cursor_y, document.cursor_x + 1, .forward));
    try testing.expectEqual(6, document.cursor_x);
    try testing.expectEqual(0, document.cursor_y);

    try testing.expect(document.search("there", document.cursor_y, document.cursor_x + 1, .forward));
    try testing.expectEqual(6, document.cursor_x);
    try testing.expectEqual(1, document.cursor_y);
}

test "searching back" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);

    document.cursor_x = 13;
    document.cursor_y = 1;
    try document.appendRow(allocator, "hello there world");
    try document.appendRow(allocator, "hello there world");
    try testing.expect(document.search("there", document.cursor_y, document.cursor_x, .backward));
    try testing.expectEqual(6, document.cursor_x);
    try testing.expectEqual(1, document.cursor_y);

    try testing.expect(document.search("there", document.cursor_y, document.cursor_x, .backward));
    try testing.expectEqual(6, document.cursor_x);
    try testing.expectEqual(0, document.cursor_y);
}

// OTHER
test "transfering row to owned text" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "world");

    const owned = try document.toOwnedText(allocator);
    defer allocator.free(owned);
    try testing.expectEqualStrings("hello\nworld", owned);
}

test "scrolling changes render x" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "a\tj");
    document.cursor_x = 2;
    document.scroll(20, 20);
    try testing.expectEqual(4, document.render_x);
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

test "transfering row to owned text with empty line" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "hello");
    try document.appendRow(allocator, "");

    const owned = try document.toOwnedText(allocator);
    defer allocator.free(owned);
    try testing.expectEqualStrings("hello\n", owned);
}

test "transfering row to owned text with empty rows" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    try document.appendRow(allocator, "");

    const owned = try document.toOwnedText(allocator);
    defer allocator.free(owned);
    try testing.expectEqualStrings("", owned);
}

test "transfering row to owned text with no rows" {
    const allocator = testing.allocator;
    var document = Editor{};
    defer document.deinit(allocator);

    const owned = try document.toOwnedText(allocator);
    defer allocator.free(owned);
    try testing.expectEqualStrings("", owned);
}
