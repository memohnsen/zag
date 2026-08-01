const std = @import("std");

const stdin_fd = std.posix.STDIN_FILENO;

pub fn enableRawMode(original_termios: std.posix.termios) !void {
    // now we edit terminal attr local flags to enter into raw mode
    var raw_termios = original_termios;
    // this takes text editing from the terminal to our program
    raw_termios.lflag.ICANON = false;
    // turns off terminal displaying so we control that and avoid possible dup
    raw_termios.lflag.ECHO = false;
    // C-C and C-Z come in as bytes rather than terminate/suspend program
    raw_termios.lflag.ISIG = false;
    // C-S and C-Q come in as bytes rather than pause/resume output
    raw_termios.iflag.IXON = false;
    // C-V and C-O come in as bytes
    raw_termios.lflag.IEXTEN = false;
    // Enter and C-M no longer comes in as new line only carriage return (these come in as the same bytes)
    raw_termios.iflag.ICRNL = false;
    // Turns off terminal processing so outgoing bytes come out as written
    raw_termios.oflag.OPOST = false;
    // Prevent terminal break condition from triggering an interrupt
    raw_termios.iflag.BRKINT = false;
    // Disable parity checking
    raw_termios.iflag.INPCK = false;
    // This normally strips the highest bit, turn off to avoid breaking UTF-8
    raw_termios.iflag.ISTRIP = false;
    // Set to 8 bit chars
    raw_termios.cflag.CSIZE = .CS8;
    // Allow read to return without receiving a byte
    raw_termios.cc[@intFromEnum(std.posix.V.MIN)] = 0;
    // Wait at most 100ms for input
    raw_termios.cc[@intFromEnum(std.posix.V.TIME)] = 1;

    // apply the changes we made and restore when done
    try std.posix.tcsetattr(stdin_fd, .FLUSH, raw_termios);
    //                                  ^ discard any unread input when changing settings
}
