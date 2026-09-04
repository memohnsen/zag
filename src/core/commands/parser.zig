const std = @import("std");
const mem = std.mem;
const testing = std.testing;

// TODO: all keypresses are stored now in editor state so they can be parsed for multi digit commands
// Matcher decides: complete → run and clear; prefix of something (3, 3g, d, gg waiting, f) → keep; invalid → beep/clear
// Parse the count from the chord when you execute
pub fn keyActionParser() !void {}
