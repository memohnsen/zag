const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const vaxis = @import("vaxis");

const config = @import("../core/config.zig");

pub const Theme = struct {
    gutter_bg: vaxis.Color = rgb(0, 0, 0),
    gutter_fg: vaxis.Color = rgb(255, 255, 255),
    status_bg: vaxis.Color = rgb(255, 255, 255),
    status_fg: vaxis.Color = rgb(0, 0, 0),
    text_fg: vaxis.Color = rgb(255, 255, 255),

    pub fn applyTheme(self: *Theme, editor_settings: *const config.Config) void {
        self.* = switch (editor_settings.theme) {
            .black_and_white => black_and_white,
            .ocean => ocean,
            .amber => amber,
            .forest => forest,
            .rose => rose,
            .slate => slate,
            .violet => violet,
        };
    }
};

pub const ThemeName = enum {
    black_and_white,
    ocean,
    amber,
    forest,
    rose,
    slate,
    violet,
};

const black_and_white: Theme = .{
    .gutter_bg = rgb(0, 0, 0),
    .gutter_fg = rgb(180, 180, 180),
    .status_bg = rgb(220, 220, 220),
    .status_fg = rgb(0, 0, 0),
    .text_fg = rgb(255, 255, 255),
};

const ocean: Theme = .{
    .gutter_bg = rgb(15, 23, 42),
    .gutter_fg = rgb(125, 211, 252),
    .status_bg = rgb(30, 58, 138),
    .status_fg = rgb(226, 232, 240),
    .text_fg = rgb(191, 219, 254),
};

const amber: Theme = .{
    .gutter_bg = rgb(28, 16, 5),
    .gutter_fg = rgb(251, 191, 36),
    .status_bg = rgb(180, 83, 9),
    .status_fg = rgb(255, 251, 235),
    .text_fg = rgb(253, 230, 138),
};

const forest: Theme = .{
    .gutter_bg = rgb(8, 20, 12),
    .gutter_fg = rgb(134, 239, 172),
    .status_bg = rgb(22, 101, 52),
    .status_fg = rgb(240, 253, 244),
    .text_fg = rgb(187, 247, 208),
};

const rose: Theme = .{
    .gutter_bg = rgb(24, 9, 14),
    .gutter_fg = rgb(251, 113, 133),
    .status_bg = rgb(159, 18, 57),
    .status_fg = rgb(255, 228, 230),
    .text_fg = rgb(254, 205, 211),
};

const slate: Theme = .{
    .gutter_bg = rgb(15, 17, 21),
    .gutter_fg = rgb(148, 163, 184),
    .status_bg = rgb(51, 65, 85),
    .status_fg = rgb(241, 245, 249),
    .text_fg = rgb(203, 213, 225),
};

const violet: Theme = .{
    .gutter_bg = rgb(18, 12, 28),
    .gutter_fg = rgb(196, 181, 253),
    .status_bg = rgb(91, 33, 182),
    .status_fg = rgb(245, 243, 255),
    .text_fg = rgb(221, 214, 254),
};

fn rgb(r: u8, g: u8, b: u8) vaxis.Color {
    return .{ .rgb = .{
        r,
        g,
        b,
    } };
}

pub fn themeName(name: []const u8) ThemeName {
    const trimmed = mem.trim(u8, name, " \"");
    if (mem.eql(u8, trimmed, "ocean")) return .ocean;
    if (mem.eql(u8, trimmed, "amber")) return .amber;
    if (mem.eql(u8, trimmed, "forest")) return .forest;
    if (mem.eql(u8, trimmed, "rose")) return .rose;
    if (mem.eql(u8, trimmed, "slate")) return .slate;
    if (mem.eql(u8, trimmed, "violet")) return .violet;
    return .black_and_white;
}

test "applyTheme sets ocean palette" {
    var theme: Theme = .{};
    const settings = config.Config{ .theme = "Ocean" };
    theme.applyTheme(&settings);
    try testing.expect(theme.gutter_bg.eql(ocean.gutter_bg));
    try testing.expect(theme.status_bg.eql(ocean.status_bg));
    try testing.expect(theme.text_fg.eql(ocean.text_fg));
}

test "applyTheme strips quotes and falls back" {
    var theme: Theme = .{};
    var amber_settings = config.Config{ .theme = "\"Amber\"" };
    theme.applyTheme(&amber_settings);
    try testing.expect(theme.status_fg.eql(amber.status_fg));

    var unknown = config.Config{ .theme = "not a theme" };
    theme.applyTheme(&unknown);
    try testing.expect(theme.gutter_bg.eql(black_and_white.gutter_bg));
}
