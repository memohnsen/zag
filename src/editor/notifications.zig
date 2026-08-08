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
    if (editor_state.save_requested) {
        try document.saveFile(allocator, io, std.Io.Dir.cwd());
        var notif_buf: [512]u8 = undefined;

        if (document.filename) |file| {
            const text = try std.fmt.bufPrint(&notif_buf, "{s} has been successfully saved.", .{file});
            try editor_state.showNotification(document, allocator, text, io);
        } else {
            const text = try std.fmt.bufPrint(&notif_buf, "Saving failed, no file name found.", .{});
            try editor_state.showNotification(document, allocator, text, io);
        }

        editor_state.save_requested = false;
    }
}

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

test "failed save message" {
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
