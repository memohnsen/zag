const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const editor = @import("editor.zig");
const state = @import("state.zig");

pub fn handleNotifications(
    editor_state: *state.State,
    document: *editor.Editor,
    allocator: mem.Allocator,
    io: std.Io,
) !void {
    var notif_buf: [512]u8 = undefined;

    if (editor_state.save_requested) {
        const result = document.saveFile(allocator, io, std.Io.Dir.cwd()) catch |e| {
            const text = try std.fmt.bufPrint(&notif_buf, "Saving failed: {}", .{e});
            try editor_state.showNotification(document, allocator, text, io);
            editor_state.save_requested = false;
            return;
        };

        switch (result) {
            .success => {
                // This is safe to unwrap bc if it got this far a filename must exist
                const text = try std.fmt.bufPrint(&notif_buf, "{s} has been successfully saved.", .{document.filename.?});
                try editor_state.showNotification(document, allocator, text, io);
            },
            .no_filename => {
                const text = try std.fmt.bufPrint(&notif_buf, "Saving failed, no file name found.", .{});
                try editor_state.showNotification(document, allocator, text, io);
                document.unsaved_edits = true;
            },
        }

        editor_state.save_requested = false;
    }

    if (editor_state.quit_blocked) {
        const text = try std.fmt.bufPrint(&notif_buf, "Please save your file before quitting or type :q! to force quit", .{});
        try editor_state.showNotification(document, allocator, text, io);
        editor_state.quit_blocked = false;
    }

    if (editor_state.invalid_command) {
        const text = try std.fmt.bufPrint(&notif_buf, "Invalid command. Valid commands include: :w, :q, :q!, :wq and, :w [filename]", .{});
        try editor_state.showNotification(document, allocator, text, io);
        editor_state.invalid_command = false;
    }

    if (editor_state.invalid_search) {
        const text = try std.fmt.bufPrint(&notif_buf, "No search results found.", .{});
        try editor_state.showNotification(document, allocator, text, io);
        editor_state.invalid_search = false;
    }
}

// -------------------------------------------------------
// -------------------------------------------------------
// TESTS
// -------------------------------------------------------
// -------------------------------------------------------

test "succesful save message" {
    const allocator = testing.allocator;
    const io = testing.io;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const file = try tmp.dir.createFile(io, "tst.txt", .{});
    defer file.close(io);

    document.filename = try allocator.dupe(u8, "./.zig-cache/tmp/tst.txt");
    editor_state.save_requested = true;
    try handleNotifications(&editor_state, &document, allocator, io);
    try testing.expectEqualStrings("./.zig-cache/tmp/tst.txt has been successfully saved.", editor_state.command_buffer.items);
    try testing.expect(editor_state.save_requested == false);
}

test "saving failed message" {
    const allocator = testing.allocator;
    const io = testing.io;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);

    document.filename = try allocator.dupe(u8, "./sample/tst.txt");
    editor_state.save_requested = true;
    document.unsaved_edits = true;
    try handleNotifications(&editor_state, &document, allocator, io);
    try testing.expect(mem.startsWith(u8, editor_state.command_buffer.items, "Saving failed:"));
    try testing.expect(editor_state.save_requested == false);
    try testing.expectEqual(true, document.unsaved_edits);
}

test "failed save message, no file name" {
    const allocator = testing.allocator;
    const io = testing.io;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);

    editor_state.save_requested = true;
    try handleNotifications(&editor_state, &document, allocator, io);
    try testing.expectEqualStrings("Saving failed, no file name found.", editor_state.command_buffer.items);
    try testing.expect(editor_state.save_requested == false);
}

test "show quit blocked" {
    const allocator = testing.allocator;
    const io = testing.io;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);

    editor_state.quit_blocked = true;
    try handleNotifications(&editor_state, &document, allocator, io);
    try testing.expectEqualStrings("Please save your file before quitting or type :q! to force quit", editor_state.command_buffer.items);
    try testing.expect(editor_state.save_requested == false);
}

test "show invalid command" {
    const allocator = testing.allocator;
    const io = testing.io;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);

    editor_state.invalid_command = true;
    try handleNotifications(&editor_state, &document, allocator, io);
    try testing.expectEqualStrings("Invalid command. Valid commands include: :w, :q, :q!, :wq and, :w [filename]", editor_state.command_buffer.items);
    try testing.expect(editor_state.invalid_command == false);
}

test "show no search results" {
    const allocator = testing.allocator;
    const io = testing.io;
    var document = editor.Editor{};
    defer document.deinit(allocator);
    var editor_state = state.State{};
    defer editor_state.deinit(allocator);

    editor_state.invalid_search = true;
    try handleNotifications(&editor_state, &document, allocator, io);
    try testing.expectEqualStrings("No search results found.", editor_state.command_buffer.items);
    try testing.expect(editor_state.invalid_search == false);
}
