const std = @import("std");
const mem = std.mem;
const ts = @import("tree_sitter");

extern fn tree_sitter_zig() callconv(.c) *ts.Language;

// These come straight from the tree_sitter_zig pkg
const highlight_query =
    \\(identifier) @variable
    \\(builtin_type) @type
    \\(builtin_identifier) @function
    \\(comment) @comment
    \\(string) @string
    \\(integer) @number
    \\(float) @number
    \\[
    \\  "pub"
    \\  "fn"
    \\  "const"
    \\  "var"
    \\  "try"
    \\  "return"
    \\  "if"
    \\  "else"
    \\  "while"
    \\  "for"
    \\  "switch"
    \\  "struct"
    \\  "enum"
    \\  "union"
    \\  "error"
    \\  "defer"
    \\  "errdefer"
    \\  "or"
    \\  "and"
    \\  "orelse"
    \\  "catch"
    \\  "break"
    \\  "continue"
    \\  "comptime"
    \\  "export"
    \\  "extern"
    \\  "packed"
    \\  "test"
    \\] @keyword
;

pub const Highlight = struct {
    start_row: u32,
    start_col: u32,
    end_row: u32,
    end_col: u32,
    name: []const u8,
};

pub const Syntax = struct {
    language: *const ts.Language,
    parser: *ts.Parser,
    tree: ?*ts.Tree = null,
    query: *ts.Query,
    allocator: mem.Allocator,
    highlights: std.ArrayList(Highlight) = .empty,

    pub fn init(allocator: mem.Allocator) !Syntax {
        const language = tree_sitter_zig();
        const parser = ts.Parser.create();
        errdefer parser.destroy();
        try parser.setLanguage(language);

        var error_offset: u32 = 0;
        const query = try ts.Query.create(language, highlight_query, &error_offset);
        errdefer query.destroy();

        return .{
            .allocator = allocator,
            .language = language,
            .parser = parser,
            .query = query,
        };
    }

    pub fn deinit(self: *Syntax) void {
        self.highlights.deinit(self.allocator);

        if (self.tree) |tree| {
            tree.destroy();
        }
        self.query.destroy();
        self.parser.destroy();
    }

    pub fn parse(self: *Syntax, source: []const u8) void {
        const new_tree = self.parser.parseString(source, null);
        if (self.tree) |old_tree| {
            old_tree.destroy();
        }
        self.tree = new_tree;
    }

    pub fn collectHighlights(self: *Syntax) !void {
        self.highlights.clearRetainingCapacity();

        const tree = self.tree orelse return;
        const cursor = ts.QueryCursor.create();
        defer cursor.destroy();
        cursor.exec(self.query, tree.rootNode());

        while (cursor.nextMatch()) |match| {
            for (match.captures) |capture| {
                const name = self.query.captureNameForId(capture.index) orelse continue;
                const start = capture.node.startPoint();
                const end = capture.node.endPoint();

                try self.highlights.append(self.allocator, .{
                    .start_row = start.row,
                    .start_col = start.column,
                    .end_row = end.row,
                    .end_col = end.column,
                    .name = name,
                });
            }
        }
    }
};
