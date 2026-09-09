const theme = @import("theme.zig");
const Theme = theme.Theme;
const rgb = theme.rgb;

pub const black_and_white: Theme = .{
    .gutter_bg = rgb(0, 0, 0),
    .gutter_fg = rgb(180, 180, 180),
    .status_bg = rgb(220, 220, 220),
    .status_fg = rgb(0, 0, 0),
    .text_fg = rgb(255, 255, 255),
};

pub const ocean: Theme = .{
    .gutter_bg = rgb(15, 23, 42),
    .gutter_fg = rgb(125, 211, 252),
    .status_bg = rgb(30, 58, 138),
    .status_fg = rgb(226, 232, 240),
    .text_fg = rgb(191, 219, 254),
};

pub const amber: Theme = .{
    .gutter_bg = rgb(28, 16, 5),
    .gutter_fg = rgb(251, 191, 36),
    .status_bg = rgb(180, 83, 9),
    .status_fg = rgb(255, 251, 235),
    .text_fg = rgb(253, 230, 138),
};

pub const forest: Theme = .{
    .gutter_bg = rgb(8, 20, 12),
    .gutter_fg = rgb(134, 239, 172),
    .status_bg = rgb(22, 101, 52),
    .status_fg = rgb(240, 253, 244),
    .text_fg = rgb(187, 247, 208),
};

pub const rose: Theme = .{
    .gutter_bg = rgb(24, 9, 14),
    .gutter_fg = rgb(251, 113, 133),
    .status_bg = rgb(159, 18, 57),
    .status_fg = rgb(255, 228, 230),
    .text_fg = rgb(254, 205, 211),
};

pub const slate: Theme = .{
    .gutter_bg = rgb(15, 17, 21),
    .gutter_fg = rgb(148, 163, 184),
    .status_bg = rgb(51, 65, 85),
    .status_fg = rgb(241, 245, 249),
    .text_fg = rgb(203, 213, 225),
};

pub const violet: Theme = .{
    .gutter_bg = rgb(18, 12, 28),
    .gutter_fg = rgb(196, 181, 253),
    .status_bg = rgb(91, 33, 182),
    .status_fg = rgb(245, 243, 255),
    .text_fg = rgb(221, 214, 254),
};
