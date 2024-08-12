const std = @import("std");

const arch = @import("arch.zig");

pub const syscall0 = arch.cpu.syscall.syscall0;
pub const syscall1 = arch.cpu.syscall.syscall1;
pub const syscall2 = arch.cpu.syscall.syscall2;
pub const syscall3 = arch.cpu.syscall.syscall3;
pub const syscall4 = arch.cpu.syscall.syscall4;
pub const syscall5 = arch.cpu.syscall.syscall5;
pub const syscall6 = arch.cpu.syscall.syscall6;

pub const console = struct {
    pub const Writer = std.io.Writer(void, error{}, printImpl);
    pub const writer = Writer{ .context = {} };

    pub fn print(comptime format: []const u8, arguments: anytype) void {
        std.fmt.format(writer, format, arguments) catch unreachable;
    }

    fn printImpl(_: void, bytes: []const u8) !usize {
        return write(0, 0, bytes);
    }
};

pub const screen = struct {
    pub const Color = packed struct(u32) {
        b: u8,
        g: u8,
        r: u8,
        padding: u8 = 0,

        pub const white: Color = .{ .r = 255, .g = 255, .b = 255 };
        pub const black: Color = .{ .r = 0, .g = 0, .b = 0 };
        pub const red: Color = .{ .r = 255, .g = 0, .b = 0 };
        pub const blue: Color = .{ .r = 0, .g = 0, .b = 255 };
        pub const green: Color = .{ .r = 0, .g = 255, .b = 0 };
    };

    pub fn put(x: usize, y: usize, color: Color) void {
        _ = syscall3(.scrput, x, y, @as(u32, @bitCast(color)));
    }

    pub fn get(x: usize, y: usize) Color {
        return @bitCast(@as(u32, @intCast(syscall2(.scrget, x, y))));
    }

    pub fn width() usize {
        return syscall0(.scrwidth);
    }

    pub fn height() usize {
        return syscall0(.scrheight);
    }
};

pub fn exit(status: u8) noreturn {
    _ = syscall1(.exit, status);

    unreachable;
}

pub fn write(fd: usize, offset: usize, buffer: []const u8) usize {
    return syscall4(.write, fd, offset, @intFromPtr(buffer.ptr), buffer.len);
}

pub fn read(fd: usize, offset: usize, buffer: []u8) usize {
    return syscall4(.read, fd, offset, @intFromPtr(buffer.ptr), buffer.len);
}

pub fn open(path: []const u8) isize {
    return @bitCast(syscall2(.open, @intFromPtr(path.ptr), path.len));
}

pub fn close(fd: usize) isize {
    return @bitCast(syscall2(.close, fd));
}

pub fn getpid() usize {
    return syscall0(.getpid);
}

pub fn kill(pid: usize) void {
    _ = syscall1(.kill, pid);
}

pub fn fork() usize {
    return syscall0(.fork);
}

pub fn execv(argv: []const [*:0]const u8) isize {
    return @bitCast(syscall2(.execv, @intFromPtr(argv.ptr), argv.len));
}
