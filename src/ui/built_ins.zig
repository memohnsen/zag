const theme = @import("theme.zig");
const Theme = theme.Theme;
const rgb = theme.rgb;

pub const default: Theme = .{
    .gutter_bg = rgb(0, 0, 0),
    .gutter_fg = rgb(107, 114, 128),
    .status_bg = rgb(22, 27, 34),
    .status_fg = rgb(216, 222, 233),
    .text_fg = rgb(216, 222, 233),
    .variable_fg = rgb(216, 222, 233),
    .keyword_fg = rgb(215, 135, 255),
    .type_fg = rgb(255, 216, 102),
    .string_fg = rgb(152, 224, 108),
    .comment_fg = rgb(107, 114, 128),
    .number_fg = rgb(255, 159, 67),
    .function_fg = rgb(90, 169, 255),
};

pub const catppuccin: Theme = .{
    .gutter_bg = rgb(0, 0, 0),
    .gutter_fg = rgb(180, 180, 180),
    .status_bg = rgb(220, 220, 220),
    .status_fg = rgb(0, 0, 0),
    .text_fg = rgb(255, 255, 255),
    .variable_fg = rgb(137, 180, 250),
    .keyword_fg = rgb(203, 166, 247),
    .type_fg = rgb(249, 226, 175),
    .string_fg = rgb(166, 227, 161),
    .comment_fg = rgb(108, 112, 134),
    .number_fg = rgb(250, 179, 135),
    .function_fg = rgb(137, 220, 235),
};

pub const ocean: Theme = .{
    .gutter_bg = rgb(15, 23, 42),
    .gutter_fg = rgb(125, 211, 252),
    .status_bg = rgb(30, 58, 138),
    .status_fg = rgb(226, 232, 240),
    .text_fg = rgb(191, 219, 254),
    .variable_fg = rgb(186, 230, 253),
    .keyword_fg = rgb(96, 165, 250),
    .type_fg = rgb(103, 232, 249),
    .string_fg = rgb(110, 231, 183),
    .comment_fg = rgb(71, 85, 105),
    .number_fg = rgb(56, 189, 248),
    .function_fg = rgb(34, 211, 238),
};

pub const amber: Theme = .{
    .gutter_bg = rgb(28, 16, 5),
    .gutter_fg = rgb(251, 191, 36),
    .status_bg = rgb(180, 83, 9),
    .status_fg = rgb(255, 251, 235),
    .text_fg = rgb(253, 230, 138),
    .variable_fg = rgb(254, 243, 199),
    .keyword_fg = rgb(251, 146, 60),
    .type_fg = rgb(252, 211, 77),
    .string_fg = rgb(253, 186, 116),
    .comment_fg = rgb(120, 80, 40),
    .number_fg = rgb(251, 191, 36),
    .function_fg = rgb(245, 158, 11),
};

pub const forest: Theme = .{
    .gutter_bg = rgb(8, 20, 12),
    .gutter_fg = rgb(134, 239, 172),
    .status_bg = rgb(22, 101, 52),
    .status_fg = rgb(240, 253, 244),
    .text_fg = rgb(187, 247, 208),
    .variable_fg = rgb(167, 243, 208),
    .keyword_fg = rgb(74, 222, 128),
    .type_fg = rgb(190, 242, 100),
    .string_fg = rgb(52, 211, 153),
    .comment_fg = rgb(74, 94, 80),
    .number_fg = rgb(163, 230, 53),
    .function_fg = rgb(45, 212, 191),
};

pub const rose: Theme = .{
    .gutter_bg = rgb(24, 9, 14),
    .gutter_fg = rgb(251, 113, 133),
    .status_bg = rgb(159, 18, 57),
    .status_fg = rgb(255, 228, 230),
    .text_fg = rgb(254, 205, 211),
    .variable_fg = rgb(254, 226, 226),
    .keyword_fg = rgb(251, 113, 133),
    .type_fg = rgb(253, 164, 175),
    .string_fg = rgb(249, 168, 212),
    .comment_fg = rgb(120, 70, 80),
    .number_fg = rgb(244, 63, 94),
    .function_fg = rgb(244, 114, 182),
};

pub const slate: Theme = .{
    .gutter_bg = rgb(15, 17, 21),
    .gutter_fg = rgb(148, 163, 184),
    .status_bg = rgb(51, 65, 85),
    .status_fg = rgb(241, 245, 249),
    .text_fg = rgb(203, 213, 225),
    .variable_fg = rgb(226, 232, 240),
    .keyword_fg = rgb(125, 211, 252),
    .type_fg = rgb(147, 197, 253),
    .string_fg = rgb(134, 239, 172),
    .comment_fg = rgb(71, 85, 105),
    .number_fg = rgb(253, 186, 116),
    .function_fg = rgb(165, 243, 252),
};

pub const violet: Theme = .{
    .gutter_bg = rgb(18, 12, 28),
    .gutter_fg = rgb(196, 181, 253),
    .status_bg = rgb(91, 33, 182),
    .status_fg = rgb(245, 243, 255),
    .text_fg = rgb(221, 214, 254),
    .variable_fg = rgb(237, 233, 254),
    .keyword_fg = rgb(192, 132, 252),
    .type_fg = rgb(216, 180, 254),
    .string_fg = rgb(249, 168, 212),
    .comment_fg = rgb(100, 80, 130),
    .number_fg = rgb(196, 181, 253),
    .function_fg = rgb(167, 139, 250),
};
