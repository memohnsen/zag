const std = @import("std");
const state = @import("../editor/state.zig");
const editor = @import("../editor/editor.zig");

pub fn runCommand(editor_state: *state.State, document: *editor.Editor, allocator: std.mem.Allocator) !bool {
    if (std.mem.eql(u8, editor_state.command_buffer.items, ":w")) {
        editor_state.save_requested = true;
        editor_state.clearText(document);
    } else if (std.mem.eql(u8, editor_state.command_buffer.items, ":wq")) {
        editor_state.save_requested = true;
        return true;
    } else if (std.mem.startsWith(u8, editor_state.command_buffer.items, ":w ")) {
        if (editor_state.command_buffer.items.len > 3) {
            const args = editor_state.command_buffer.items[3..];
            const filename = std.mem.trim(u8, args, " ");
            if (filename.len > 0) {
                try document.setFilenameAs(allocator, filename);
            }
        }

        editor_state.save_requested = true;
        editor_state.clearText(document);
    } else if (std.mem.eql(u8, editor_state.command_buffer.items, ":q") and !document.unsaved_edits) {
        return true;
    } else if (std.mem.eql(u8, editor_state.command_buffer.items, ":q!")) {
        return true;
    } else if (std.mem.eql(u8, editor_state.command_buffer.items, ":q") and document.unsaved_edits) {
        editor_state.quit_blocked = true;
    } else {
        editor_state.invalid_command = true;
    }

    return false;
}
