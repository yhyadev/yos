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
        return write(1, 0, bytes);
    }

    pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
        print("\npanic: {s}\n", .{message});

        exit(1);
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
    pub const Protection = enum(u8) {
        none = 0x0,
        read = 0x1,
        write = 0x2,
        execute = 0x4,
        write_execute = 0x2 | 0x4,
    };

    pub fn map(virtual_address_hint: usize, bytes_len: usize, protection: Protection) ?[*]u8 {
        return @ptrFromInt(syscall4(.mmap, virtual_address_hint, bytes_len, @intFromEnum(protection), 0));
    }

    pub fn unmap(bytes: []u8) void {
        _ = syscall2(.munmap, @intFromPtr(bytes.ptr), bytes.len);
    }

    pub fn allocator() std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = undefined,
            .vtable = &Allocator.vtable,
        };
    }

    pub const Allocator = struct {
        pub const vtable: std.mem.Allocator.VTable = .{
            .alloc = alloc,
            .resize = std.mem.Allocator.noResize,
            .free = free,
        };

        fn alloc(_: *anyopaque, bytes_len: usize, _: u8, _: usize) ?[*]u8 {
            return map(0, bytes_len, .write);
        }

        fn free(_: *anyopaque, bytes: []u8, _: u8, _: usize) void {
            unmap(bytes);
        }
    };
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
