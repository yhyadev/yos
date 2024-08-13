const std = @import("std");
const abi = @import("abi");

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
    pub fn put(x: usize, y: usize, color: abi.Color) void {
        _ = syscall3(.scrput, x, y, @as(u32, @bitCast(color)));
    }

    pub fn get(x: usize, y: usize) abi.Color {
        return @bitCast(@as(u32, @intCast(syscall2(.scrget, x, y))));
    }

    pub fn width() usize {
        return syscall0(.scrwidth);
    }

    pub fn height() usize {
        return syscall0(.scrheight);
    }
};

pub const keyboard = struct {
    pub fn poll() ?abi.KeyEvent {
        const maybe_key: isize = @bitCast(syscall1(.poll, 1));

        if (maybe_key == -1) {
            return null;
        }

        return @bitCast(@as(u8, @intCast(maybe_key)));
    }
};

pub const memory = struct {
    pub fn allocator() std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = undefined,
            .vtable = &.{
                .alloc = &alloc,
                .resize = std.mem.Allocator.noResize,
                .free = &free,
            },
        };
    }

    fn alloc(_: *anyopaque, bytes_len: usize, _: u8, _: usize) ?[*]u8 {
        return @ptrFromInt(syscall1(.alloc, bytes_len));
    }

    fn free(_: *anyopaque, bytes: []u8, _: u8, _: usize) void {
        _ = syscall2(.free, @intFromPtr(bytes.ptr), bytes.len);
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
