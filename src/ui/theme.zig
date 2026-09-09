const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const vaxis = @import("vaxis");

const config = @import("../core/config.zig");
const built_ins = @import("built_ins.zig");

const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub const ThemeName = union(enum) {
    black_and_white,
    ocean,
    amber,
    forest,
    rose,
    slate,
    violet,
    custom: []const u8,
};

pub const Theme = struct {
    gutter_bg: vaxis.Color = rgb(0, 0, 0),
    gutter_fg: vaxis.Color = rgb(255, 255, 255),
    status_bg: vaxis.Color = rgb(255, 255, 255),
    status_fg: vaxis.Color = rgb(0, 0, 0),
    text_fg: vaxis.Color = rgb(255, 255, 255),

    pub fn applyTheme(
        self: *Theme,
        editor_settings: *const config.Config,
        io: std.Io,
        allocator: mem.Allocator,
        home_dir: []const u8,
    ) void {
        self.* = switch (themeName(editor_settings.theme)) {
            .black_and_white => built_ins.black_and_white,
            .ocean => built_ins.ocean,
            .amber => built_ins.amber,
            .forest => built_ins.forest,
            .rose => built_ins.rose,
            .slate => built_ins.slate,
            .violet => built_ins.violet,
            .custom => loadCustomTheme(io, allocator, home_dir, editor_settings) catch built_ins.black_and_white,
        };
    }
};

/// if theme is not built in then we find the file that matches that theme in themes/
/// iter through file to get vals and set theme to those
pub fn loadCustomTheme(
    io: std.Io,
    allocator: mem.Allocator,
    home_dir: []const u8,
    editor_settings: *const config.Config,
) !Theme {
    const file_name = try std.fmt.allocPrint(allocator, "{s}.toml", .{editor_settings.theme});
    defer allocator.free(file_name);
    const file_path = try std.fs.path.join(allocator, &.{
        home_dir,
        ".config",
        "zag",
        "themes",
        file_name,
    });
    defer allocator.free(file_path);

    const file = try std.Io.Dir.openFileAbsolute(
        io,
        file_path,
        .{},
    );
    defer file.close(io);

    var read_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buffer);

    const contents = try file_reader.interface.allocRemaining(
        allocator,
        .unlimited,
    );
    defer allocator.free(contents);

    var gutter_bg: Rgb = undefined;
    var gutter_fg: Rgb = undefined;
    var status_bg: Rgb = undefined;
    var status_fg: Rgb = undefined;
    var text_fg: Rgb = undefined;

    var lines = mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        if (mem.eql(u8, line, "[theme]")) {
            continue;
        }

        const trimmed = mem.trim(u8, line, " ");
        if (mem.startsWith(u8, trimmed, "gutter_bg = ")) {
            gutter_bg = try hexToRgb(trimmed["gutter_bg = ".len..]);
            continue;
        }
        if (mem.startsWith(u8, trimmed, "gutter_fg = ")) {
            gutter_fg = try hexToRgb(trimmed["gutter_fg = ".len..]);
            continue;
        }
        if (mem.startsWith(u8, trimmed, "status_bg = ")) {
            status_bg = try hexToRgb(trimmed["status_bg = ".len..]);
            continue;
        }
        if (mem.startsWith(u8, trimmed, "status_fg = ")) {
            status_fg = try hexToRgb(trimmed["status_fg = ".len..]);
            continue;
        }
        if (mem.startsWith(u8, trimmed, "text_fg = ")) {
            text_fg = try hexToRgb(trimmed["text_fg = ".len..]);
            continue;
        }
    }

    return Theme{
        .gutter_bg = rgb(gutter_bg.r, gutter_bg.g, gutter_bg.b),
        .gutter_fg = rgb(gutter_fg.r, gutter_fg.g, gutter_fg.b),
        .status_bg = rgb(status_bg.r, status_bg.g, status_bg.b),
        .status_fg = rgb(status_fg.r, status_fg.g, status_fg.b),
        .text_fg = rgb(text_fg.r, text_fg.g, text_fg.b),
    };
}

pub fn rgb(r: u8, g: u8, b: u8) vaxis.Color {
    return .{ .rgb = .{
        r,
        g,
        b,
    } };
}

fn hexToRgb(hex: []const u8) !Rgb {
    const trimmed = mem.trim(u8, hex, "\"");
    var start: usize = 0;
    if (trimmed.len > 0 and trimmed[0] == '#') {
        start = 1;
    }

    if (trimmed.len - start != 6) {
        return error.InvalidHexLength;
    }

    const r = try std.fmt.parseInt(u8, trimmed[start .. start + 2], 16);
    const g = try std.fmt.parseInt(u8, trimmed[start + 2 .. start + 4], 16);
    const b = try std.fmt.parseInt(u8, trimmed[start + 4 .. start + 6], 16);

    return Rgb{
        .r = r,
        .g = g,
        .b = b,
    };
}

fn themeName(name: []const u8) ThemeName {
    const trimmed = mem.trim(u8, name, " \"");
    if (mem.eql(u8, trimmed, "ocean")) return .ocean;
    if (mem.eql(u8, trimmed, "amber")) return .amber;
    if (mem.eql(u8, trimmed, "forest")) return .forest;
    if (mem.eql(u8, trimmed, "rose")) return .rose;
    if (mem.eql(u8, trimmed, "slate")) return .slate;
    if (mem.eql(u8, trimmed, "violet")) return .violet;
    if (mem.eql(u8, trimmed, "black_and_white")) return .black_and_white;

    return .{ .custom = name };
}

test "applyTheme sets ocean palette" {
    var theme: Theme = .{};
    const io = testing.io;
    const allocator = testing.allocator;
    const ocean = built_ins.ocean;
    const settings = config.Config{ .theme = "ocean" };
    theme.applyTheme(&settings, io, allocator, "./.zig-cache/tmp/");

    try testing.expect(theme.gutter_bg.eql(ocean.gutter_bg));
    try testing.expect(theme.status_bg.eql(ocean.status_bg));
    try testing.expect(theme.text_fg.eql(ocean.text_fg));
}

test "applyTheme strips quotes and falls back" {
    var theme: Theme = .{};
    const amber = built_ins.amber;
    const io = testing.io;
    const allocator = testing.allocator;
    var amber_settings = config.Config{ .theme = "\"amber\"" };
    theme.applyTheme(&amber_settings, io, allocator, "./.zig-cache/tmp/");

    try testing.expect(theme.status_fg.eql(amber.status_fg));

    const black_and_white = built_ins.black_and_white;
    var unknown = config.Config{ .theme = "not a theme" };
    theme.applyTheme(&unknown, io, allocator, "./.zig-cache/tmp/");

    try testing.expect(theme.gutter_bg.eql(black_and_white.gutter_bg));
}

test "applyTheme reverts to black and white if custom theme has no toml" {
    var theme: Theme = .{};
    const editor_settings: config.Config = .{};
    const io = testing.io;
    const allocator = testing.allocator;
    const settings = config.Config{ .theme = "red" };
    theme.applyTheme(&settings, io, allocator, "./.zig-cache/tmp/");

    try testing.expectEqual(editor_settings.theme, "black_and_white");
}

test "hex to RGB works" {
    try testing.expectEqual(hexToRgb("#FF0000"), Rgb{
        .r = 255,
        .g = 0,
        .b = 0,
    });

    try testing.expectEqual(hexToRgb("#00FF00"), Rgb{
        .r = 0,
        .g = 255,
        .b = 0,
    });

    try testing.expectEqual(hexToRgb("#0000FF"), Rgb{
        .r = 0,
        .g = 0,
        .b = 255,
    });
}
