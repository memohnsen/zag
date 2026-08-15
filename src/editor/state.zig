const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const editor = @import("editor.zig");

pub const State = struct {
    // Command line text
    command_buffer: std.ArrayList(u8) = .empty,
    // Last search term in command buffer for n and N
    last_search: std.ArrayList(u8) = .empty,
    // Cursor location in command line
    command_cursor_x: usize = 0,
    // where the cursor was prior to entering the command buffer
    cursor_origin_x: usize = 0,
    cursor_origin_y: usize = 0,

    // These flags can be changed via keys in src/commands.zig
    // if :w or :wq was entered
    save_requested: bool = false,
    // is a notif showing in the buffer or not
    notif_started: ?std.Io.Timestamp = null,
    // true if edits are not saved and :q! is not entered
    quit_blocked: bool = false,
    // not one of the predefined options
    invalid_command: bool = false,
    // search term not found
    invalid_search: bool = false,
    // pending chars for multichar motions like gg, gl, gh, dd
    pending_g: bool = false,
    pending_d: bool = false,
    // whether R was hit
    replace_mult: bool = false,

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        self.command_buffer.deinit(allocator);
        self.last_search.deinit(allocator);
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

    pub fn setLastSearch(self: *State, allocator: mem.Allocator) !void {
        self.last_search.clearRetainingCapacity();
        if (self.command_buffer.items.len < 2) return;
        try self.last_search.appendSlice(allocator, self.command_buffer.items[1..]);
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

// -------------------------------------------------------
// -------------------------------------------------------
// TESTS
// -------------------------------------------------------
// -------------------------------------------------------

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

test "notification stays before 3s" {
    const allocator = testing.allocator;
    const io = testing.io;
    var editor_state = State{};
    defer editor_state.deinit(allocator);
    var document = editor.Editor{};
    defer document.deinit(allocator);

    try editor_state.showNotification(&document, allocator, "File saved", io);

    const now = std.Io.Timestamp.now(io, .awake);
    editor_state.notif_started = now.subDuration(std.Io.Duration.fromSeconds(2));
    editor_state.hideNotification(&document, io);

    try testing.expectEqualStrings("File saved", editor_state.command_buffer.items);
    try testing.expect(editor_state.notif_started != null);
}

test "hide notification does nothing when none is showing" {
    const allocator = testing.allocator;
    const io = testing.io;
    var editor_state = State{};
    defer editor_state.deinit(allocator);
    var document = editor.Editor{};
    defer document.deinit(allocator);

    editor_state.hideNotification(&document, io);

    try testing.expect(editor_state.command_buffer.items.len == 0);
    try testing.expect(editor_state.notif_started == null);
}

test "last search is set from command buffer" {
    var state = State{};
    const allocator = testing.allocator;
    defer state.deinit(allocator);

    try state.insertText(allocator, 0, "/hello");
    try state.setLastSearch(allocator);

    try testing.expectEqualStrings("hello", state.last_search.items);
}

test "last search is replaced by new search" {
    var state = State{};
    const allocator = testing.allocator;
    defer state.deinit(allocator);
    var document = editor.Editor{};
    defer document.deinit(allocator);

    try state.insertText(allocator, 0, "/foo");
    try state.setLastSearch(allocator);
    state.clearText(&document);

    try state.insertText(allocator, 0, "/bar");
    try state.setLastSearch(allocator);

    try testing.expectEqualStrings("bar", state.last_search.items);
}

test "last search empty with only slash" {
    var state = State{};
    const allocator = testing.allocator;
    defer state.deinit(allocator);

    try state.insertText(allocator, 0, "/");
    try state.setLastSearch(allocator);

    try testing.expectEqualStrings("", state.last_search.items);
}

test "last search empty with empty command buffer" {
    var state = State{};
    const allocator = testing.allocator;
    defer state.deinit(allocator);

    try state.setLastSearch(allocator);

    try testing.expectEqualStrings("", state.last_search.items);
}

test "last search cleared when buffer empties" {
    var state = State{};
    const allocator = testing.allocator;
    defer state.deinit(allocator);
    var document = editor.Editor{};
    defer document.deinit(allocator);

    try state.insertText(allocator, 0, "/foo");
    try state.setLastSearch(allocator);
    state.clearText(&document);
    try state.setLastSearch(allocator);

    try testing.expectEqualStrings("", state.last_search.items);
}
