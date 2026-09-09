const std = @import("std");
const mem = std.mem;

const editor_theme = @import("../ui/theme.zig");

const LineNumbers = enum {
    normal,
    relative,
};

pub const Config = struct {
    scroll_buffer: u16 = 5,
    line_numbers: LineNumbers = .relative,
    theme: []const u8 = "black_and_white",

    pub fn deinit(self: *Config, allocator: mem.Allocator) void {
        allocator.free(self.theme);
    }

    // TODO: add tests for this
    // do this anytime the editor is open
    pub fn readConfig(
        self: *Config,
        allocator: mem.Allocator,
        io: std.Io,
        home_dir: []const u8,
    ) !void {
        const file_path = try std.fs.path.join(allocator, &.{
            home_dir,
            ".config",
            "zag",
            "config.toml",
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

        var lines = mem.splitScalar(u8, contents, '\n');
        while (lines.next()) |line| {
            if (mem.eql(u8, line, "[editor]")) {
                continue;
            }

            const trimmed = mem.trim(u8, line, " ");
            if (mem.startsWith(u8, trimmed, "scroll_buffer = ")) {
                const val = std.fmt.parseInt(u16, line["scroll_buffer = ".len..], 10) catch 5;
                self.scroll_buffer = val;
                continue;
            } else if (mem.startsWith(u8, trimmed, "line_numbers = ")) {
                self.line_numbers = std.meta.stringToEnum(LineNumbers, trimmed) orelse .relative;
                continue;
            } else if (mem.startsWith(u8, trimmed, "theme = ")) {
                const trim_quotes = mem.trim(u8, trimmed["theme = ".len..], "\"");
                self.theme = try allocator.dupe(u8, trim_quotes);
                continue;
            }
        }
    }

    // this needs to be done only when first opening the editor if the file does not already exist
    // create the file and load in defaults
    pub fn writeConfig(
        self: *const Config,
        allocator: mem.Allocator,
        io: std.Io,
        home_dir: []const u8,
    ) !void {
        const config_dir_path = try std.fs.path.join(allocator, &.{
            home_dir,
            ".config",
            "zag",
        });
        defer allocator.free(config_dir_path);

        const file_path = try std.fs.path.join(allocator, &.{
            config_dir_path,
            "config.toml",
        });
        defer allocator.free(file_path);

        var home = try std.Io.Dir.cwd().openDir(io, home_dir, .{});
        defer home.close(io);

        try home.createDirPath(io, ".config/zag");

        const file = std.Io.Dir.createFileAbsolute(io, file_path, .{
            .exclusive = true,
        }) catch |err| switch (err) {
            error.PathAlreadyExists => return,
            else => return err,
        };

        defer file.close(io);

        var buf: [512]u8 = undefined;
        const file_text = try std.fmt.bufPrint(
            &buf,
            \\[editor]
            \\# how many lines between the cursor and the edge of the editor before scrolling begins
            \\scroll_buffer = {d}
            \\# relative or normal
            \\line_numbers = "{s}"
            \\# black_and_white, ocean, amber, forest, rose, slate, paper, violet
            \\# Custom themes can be added by putting placing a file in zag/themes/FILENAME.toml
            \\# FILENAME and the theme name below must be the same
            \\# see ./examples/themes/red.toml for an example custom theme
            \\theme = "{s}"
        ,
            .{
                self.scroll_buffer,
                @tagName(self.line_numbers),
                self.theme,
            },
        );

        try file.writeStreamingAll(io, file_text);
    }
};
