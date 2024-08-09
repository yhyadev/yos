//! Teletype
//!
//! A small terninal emulation so we can display messages on screen

const std = @import("std");

const arch = @import("arch.zig");
const screen = @import("screen.zig");
const vfs = @import("fs/vfs.zig");

const SpinLock = @import("locks/SpinLock.zig");

var mutex: SpinLock = .{};

/// The font that we use for drawing on the screen, all fields must be known at compile time
/// and never changed
const font: Font = .{
    .data = @embedFile("assets/fonts/vga8x16.bin"),
    .text_width = 8,
    .text_height = 16,
};

const Font = struct {
    /// A Bit Map containing the shape of each character, it must be compatible with
    /// the ASCII Table so we can get the shape using the character itself
    data: []const u8,
    text_width: usize,
    text_height: usize,
};

/// The current state of the tty, used for keeping the current x and y or other information, it
/// is public so you can change the background or foreground (don't touch other fields)
pub var state: State = .{};

pub const State = struct {
    background: screen.Color = screen.Color.black,
    foreground: screen.Color = screen.Color.white,
    width: usize = 0,
    height: usize = 0,
    x: usize = 0,
    y: usize = 0,
};

pub const Writer = std.io.Writer(void, error{}, printImpl);
pub const writer = Writer{ .context = {} };

pub const device: vfs.FileSystem.Node = .{
    .name = "tty",
    .tag = .file,
    .vtable = &.{
        .write = struct {
            fn write(_: *vfs.FileSystem.Node, _: usize, buffer: []const u8) usize {
                print("{s}", .{buffer});

                return buffer.len;
            }
        }.write,
    },
};

pub fn clear() void {
    mutex.lock();
    defer mutex.unlock();

    for (0..screen.framebuffer.height) |y| {
        for (0..screen.framebuffer.width) |x| {
            screen.get(x, y).* = state.background;
        }
    }

    state.x = 0;
    state.y = 0;
}

pub fn print(comptime format: []const u8, arguments: anytype) void {
    mutex.lock();
    defer mutex.unlock();

    std.fmt.format(writer, format, arguments) catch arch.hang();
}

fn printImpl(_: void, bytes: []const u8) !usize {
    for (bytes) |byte| {
        printByte(byte);
    }

    return bytes.len;
}

fn printByte(byte: u8) void {
    if (!std.ascii.isAscii(byte)) {
        printFontBytes(getFontBytes(font.data.len - 2 * 16));
    } else if (byte != '\n') {
        printFontBytes(getFontBytes(@mod(byte * font.text_height, font.data.len)));
    }

    if (state.x + 1 >= state.width or byte == '\n') {
        printNewLine();
    } else {
        state.x += 1;
    }
}

fn printNewLine() void {
    state.x = 0;
    state.y += 1;

    if (state.y >= state.height) {
        mutex.unlock();
        clear();
        mutex.lock();

        state.y = 0;
    }
}

fn getFontBit(x: usize, y: usize, font_bytes: []const u8) bool {
    return (font_bytes[y] & std.math.pow(u8, 2, @intCast(x))) != 0;
}

fn getFontBytes(location: usize) []const u8 {
    return font.data[location .. location + font.text_height];
}

fn printFontBytes(font_bytes: []const u8) void {
    const x = state.x * font.text_width;
    const y = state.y * font.text_height;

    for (0..font.text_height) |dy| {
        for (0..font.text_width) |dx| {
            const font_bit = getFontBit(font.text_width - 1 - dx, dy, font_bytes);

            if (font_bit) {
                screen.get(x + dx, y + dy).* = state.foreground;
            } else {
                screen.get(x + dx, y + dy).* = state.background;
            }
        }
    }
}

pub fn init() void {
    state.width = @divFloor(screen.framebuffer.width, font.text_width);
    state.height = @divFloor(screen.framebuffer.height, font.text_height);

    clear();
}
