const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const vaxis = @import("vaxis");

const commands = @import("commands.zig");
const editor = @import("../editor/editor.zig");
const state = @import("../editor/state.zig");

// all keypresses are stored now in editor state so they can be parsed for multi digit commands
// Matcher decides: complete → run and clear; prefix of something (3, 3g, d, gg waiting, f) → keep; invalid → beep/clear
// Parse the count from the chord when you execute
pub fn keyActionParser(key: vaxis.Key, document: *editor.Editor, editor_state: *state.State) commands.Command {
    // TODO: items are stored in state
    // every keypress parse that state
    // if whats in there matches a command, run it and clear buffer
    // else continue
    //
    // this becomes a rewrite of commandFromKey
    // rather than matching on key byte
    // we get the state array, split into nums and letters
    // match letters to valid commands
    // repeat nums times

    if (document.mode == .NORMAL) {
        if (key.matches('d', .{ .ctrl = true })) return .page_down;
        if (key.matches('u', .{ .ctrl = true })) return .page_up;
    }

    return switch (key.codepoint) {
        vaxis.Key.escape => .normal,

        vaxis.Key.left => .left,
        vaxis.Key.right => .right,
        vaxis.Key.up => .up,
        vaxis.Key.down => .down,

        vaxis.Key.enter => if (document.mode == .NORMAL) {
            return .down;
        } else if (document.mode == .INSERT) {
            return .carriage_return;
        } else if (document.mode == .COMMAND) {
            return .run_command;
        } else if (document.mode == .SEARCH) {
            return .run_search;
        } else {
            return .normal;
        },
        vaxis.Key.tab => if (document.mode == .INSERT) {
            return .tab;
        } else {
            return .right;
        },
        vaxis.Key.backspace => if (document.mode == .NORMAL) {
            return .left;
        } else {
            return .delete_left;
        },

        else => if (document.mode == .NORMAL) {
            // walk through each char of the keys until we find a letter
            // at that point we know where the slices are for numbers and letters
            var cutoff_index: u8 = 0;
            while (cutoff_index < editor_state.pending_motion_len) : (cutoff_index += 1) {
                if (!std.ascii.isAlphabetic(editor_state.pending_motion[cutoff_index])) {
                    continue;
                } else {
                    break;
                }
            }

            // const count = editor_state.pending_motion[0..cutoff_index];
            const letters = editor_state.pending_motion[cutoff_index..editor_state.pending_motion_len];

            // NAVIGATION
            if (mem.eql(u8, "G", letters)) return .document_end;
            if (mem.eql(u8, "0", letters)) return .line_start;
            if (mem.eql(u8, "gh", letters)) return .first_char;
            if (mem.eql(u8, "_", letters)) return .first_char;
            if (mem.eql(u8, "$", letters)) return .line_end;
            if (mem.eql(u8, "l", letters)) return .line_end;
            if (mem.eql(u8, "gg", letters)) return .doc_start_gg;
            if (mem.eql(u8, "H", letters)) return .top;
            if (mem.eql(u8, "M", letters)) return .middle;
            if (mem.eql(u8, "L", letters)) return .bottom;
            if (mem.eql(u8, "w", letters)) return .next_word_start;
            if (mem.eql(u8, "W", letters)) return .next_space_start;
            if (mem.eql(u8, "e", letters)) return .next_word_end;
            if (mem.eql(u8, "E", letters)) return .next_space_end;
            if (mem.eql(u8, "b", letters)) return .last_word_start;
            if (mem.eql(u8, "B", letters)) return .last_space_start;
            if (mem.eql(u8, "}", letters)) return .next_empty_row;
            if (mem.eql(u8, "{", letters)) return .prev_empty_row;

            if (mem.eql(u8, "h", letters)) return .left;
            if (mem.eql(u8, "j", letters)) return .down;
            if (mem.eql(u8, "k", letters)) return .up;
            if (mem.eql(u8, "l", letters)) return .right;

            // INSERTION
            if (mem.eql(u8, "i", letters)) return .insert_left;
            if (mem.eql(u8, "I", letters)) return .insert_start;
            if (mem.eql(u8, "a", letters)) return .insert_right;
            if (mem.eql(u8, "A", letters)) return .insert_end;
            if (mem.eql(u8, "o", letters)) return .new_line_down;
            if (mem.eql(u8, "O", letters)) return .new_line_up;

            // MANIPULATION
            if (mem.eql(u8, "J", letters)) return .join_next_line;
            if (mem.eql(u8, "s", letters)) return .substitute_char;
            if (mem.eql(u8, "S", letters)) return .substitute_line;

            // DELETION
            if (mem.eql(u8, "x", letters)) return .delete_current;
            if (mem.eql(u8, "X", letters)) return .delete_left;
            if (mem.eql(u8, "dd", letters)) return .delete_line;
            if (mem.eql(u8, "D", letters)) return .delete_line_remaining;

            // MODES
            if (mem.eql(u8, "r", letters)) return .replace;
            if (mem.eql(u8, "R", letters)) return .replace_mult;
            if (mem.eql(u8, "v", letters)) return .visual;
            if (mem.eql(u8, "V", letters)) return .visual;
            if (mem.eql(u8, ":", letters)) return .command;
            if (mem.eql(u8, "/", letters)) return .search;
            if (mem.eql(u8, "n", letters)) return .search_next;
            if (mem.eql(u8, "N", letters)) return .search_prev;

            return .normal;
        } else {
            return .other;
        },
    };
}

// fn commandFromKey(key: vaxis.Key, document: *editor.Editor, pending_g: bool) Command {
//
//
// }

test "G returns document_end" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    try testing.expectEqual(.document_end, keyActionParser(.{
        .codepoint = 'G',
        .text = "G",
    }, &document, &editor_state));
}

test "multi char commands work" {
    const allocator = testing.allocator;
    var document: editor.Editor = .{};
    defer document.deinit(allocator);
    var editor_state: state.State = .{};

    editor_state.pending_motion_len = 2;
    @memcpy(editor_state.pending_motion[0..editor_state.pending_motion_len], "dd");
    try testing.expectEqual(.delete_line, keyActionParser(.{ .codepoint = 'd' }, &document, &editor_state));
}
