const std = @import("std");
const abi = @import("abi");

const arch = @import("arch.zig");
const higher_half = @import("higher_half.zig");
const scheduler = @import("scheduler.zig");
const screen = @import("screen.zig");
const stream = @import("stream.zig");
const tmpfs = @import("fs/tmpfs.zig");

pub fn write(context: *arch.cpu.process.Context, fd: usize, offset: usize, buffer_ptr: usize, buffer_len: usize) void {
    const buffer = @as([*]u8, @ptrFromInt(buffer_ptr))[0..buffer_len];

    const process = scheduler.maybe_process.?;

    context.rax = process.writeFile(fd, offset, buffer);
}

pub fn read(context: *arch.cpu.process.Context, fd: usize, offset: usize, buffer_ptr: usize, buffer_len: usize) void {
    const buffer = @as([*]u8, @ptrFromInt(buffer_ptr))[0..buffer_len];

    const process = scheduler.maybe_process.?;

    context.rax = process.readFile(fd, offset, buffer);
}

pub fn open(context: *arch.cpu.process.Context, path_ptr: usize, path_len: usize) void {
    const path = @as([*]u8, @ptrFromInt(path_ptr))[0..path_len];

    const process = scheduler.maybe_process.?;

    const result: *isize = @ptrCast(&context.rax);

    result.* = process.openFile(path) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
        error.NotFound => -1,
        error.NotDirectory => -2,
        error.PathNotAbsolute => -3,
    };
}

pub fn close(context: *arch.cpu.process.Context, fd: usize) void {
    const process = scheduler.maybe_process.?;

    const result: *isize = @ptrCast(&context.rax);

    result.* = 0;

    process.closeFile(fd) catch |err| switch (err) {
        error.NotFound => result.* = -1,
    };
}

pub fn poll(context: *arch.cpu.process.Context, sid: usize) void {
    const result: *isize = @ptrCast(&context.rax);

    result.* = -1;

    if (sid == 1) {
        if (stream.key_events.poll()) |key_event| {
            result.* = @as(u8, @bitCast(key_event));
        }
    }
}

pub fn exit(context: *arch.cpu.process.Context, _: usize) void {
    const process = scheduler.maybe_process.?;

    kill(context, process.id);
}

pub fn kill(context: *arch.cpu.process.Context, pid: usize) void {
    scheduler.kill(pid);

    scheduler.reschedule(context) catch @panic("out of memory");
}

pub fn getpid(context: *arch.cpu.process.Context) void {
    const process = scheduler.maybe_process.?;

    context.rax = process.id;
}

pub fn fork(context: *arch.cpu.process.Context) void {
    context.rax = scheduler.fork(context) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
    };
}

pub fn execve(context: *arch.cpu.process.Context, argv_ptr: usize, argv_len: usize, env_ptr: usize, env_len: usize) void {
    const argv = @as([*]const [*:0]const u8, @ptrFromInt(argv_ptr))[0..argv_len];
    const env = @as([*]const [*:0]const u8, @ptrFromInt(env_ptr))[0..env_len];

    const result: *isize = @ptrCast(&context.rax);

    result.* = 0;

    scheduler.execve(context, argv, env) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
        error.NotFound => result.* = -1,
        error.NotDirectory => result.* = -2,
        error.PathNotAbsolute => result.* = -3,
        error.BadElf => result.* = -4,
        error.BadEnvPair => result.* = -5,
    };
}

pub fn scrput(_: *arch.cpu.process.Context, x: usize, y: usize, color_64: usize) void {
    const color_32: u32 = @truncate(color_64);
    const color: abi.Color = @bitCast(color_32);

    screen.get(x, y).* = color;
}

pub fn scrget(context: *arch.cpu.process.Context, x: usize, y: usize) void {
    const result: *abi.Color = @ptrCast(&context.rax);

    result.* = screen.get(x, y).*;
}

pub fn scrwidth(context: *arch.cpu.process.Context) void {
    context.rax = screen.framebuffer.width;
}

pub fn scrheight(context: *arch.cpu.process.Context) void {
    context.rax = screen.framebuffer.height;
}

pub fn envput(context: *arch.cpu.process.Context, env_pair_ptr: usize, env_pair_len: usize) void {
    const env_pair = @as([*]const u8, @ptrFromInt(env_pair_ptr))[0..env_pair_len];

    const process = scheduler.maybe_process.?;

    const result: *isize = @ptrCast(&context.rax);

    result.* = 0;

    process.putEnvPair(env_pair) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
        error.BadEnvPair => result.* = -1,
    };
}

pub fn envget(context: *arch.cpu.process.Context, env_key_ptr: usize, env_key_len: usize) void {
    const env_key = @as([*]const u8, @ptrFromInt(env_key_ptr))[0..env_key_len];

    const process = scheduler.maybe_process.?;

    context.rax = 0;

    const env_value = process.env.get(env_key) orelse return;

    const env_value_z = user_allocator.dupeZ(u8, env_value) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
    };

    context.rax = @intCast(@intFromPtr(env_value_z.ptr));
}

const user_allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &struct {
        pub const vtable: std.mem.Allocator.VTable = .{
            .alloc = alloc,
            .resize = std.mem.Allocator.noResize,
            .free = free,
        };

        fn alloc(_: *anyopaque, bytes_len: usize, _: u8, _: usize) ?[*]u8 {
            var context: arch.cpu.process.Context = .{};
            mmap(&context, 0, bytes_len, 2, 0);
            return @ptrFromInt(context.rax);
        }

        fn free(_: *anyopaque, bytes: []u8, _: u8, _: usize) void {
            munmap(undefined, @intFromPtr(bytes.ptr), bytes.len);
        }
    }.vtable,
};

pub fn mmap(context: *arch.cpu.process.Context, virtual_address_hint: usize, bytes_len: usize, protection: usize, _: usize) void {
    const process = scheduler.maybe_process.?;

    const scoped_allocator = process.arena.allocator();

    const page_table = arch.paging.getActivePageTable();

    const page_count = std.math.divCeil(usize, bytes_len, std.mem.page_size) catch unreachable;

    context.rax = 0;

    const bytes = scoped_allocator.alignedAlloc(u8, std.mem.page_size, bytes_len) catch return;

    const physical_address = page_table.physicalFromVirtual(@intFromPtr(bytes.ptr)).?;

    const min_virtual_address = 0x10000;

    var virtual_address: usize = min_virtual_address;

    while (virtual_address < std.math.maxInt(usize)) : (virtual_address += std.mem.page_size) {
        if (!page_table.mapped(virtual_address)) retry: {
            for (1..page_count) |i| {
                if (page_table.mapped(virtual_address + i * std.mem.page_size)) {
                    virtual_address += i * std.mem.page_size;

                    break :retry;
                }
            }

            for (0..page_count) |i| {
                const offsetted_virtual_address = virtual_address + i * std.mem.page_size;
                const offsetted_physical_address = physical_address + i * std.mem.page_size;

                page_table.map(
                    scoped_allocator,
                    offsetted_virtual_address,
                    offsetted_physical_address,
                    .{
                        .user = true,
                        .global = false,
                        .writable = (protection & 0x2) != 0,
                        .executable = (protection & 0x4) != 0,
                    },
                ) catch {
                    return;
                };
            }

            context.rax = virtual_address;

            return;
        }

        if (virtual_address == min_virtual_address and virtual_address_hint != 0) {
            virtual_address = std.mem.alignForward(usize, virtual_address_hint, std.mem.page_size) - std.mem.page_size;
        }
    }
}

pub fn munmap(_: *arch.cpu.process.Context, bytes_ptr: usize, bytes_len: usize) void {
    const process = scheduler.maybe_process.?;

    const scoped_allocator = process.arena.allocator();

    const page_table = arch.paging.getActivePageTable();

    const page_count = std.math.divCeil(usize, bytes_len, std.mem.page_size) catch unreachable;

    scoped_allocator.free(@as([*]u8, @ptrFromInt(higher_half.virtualFromPhysical(page_table.physicalFromVirtual(bytes_ptr).?)))[0..bytes_len]);

    for (0..page_count) |i| {
        page_table.unmap(bytes_ptr + i * std.mem.page_size);
    }
}

pub fn mkdir(context: *arch.cpu.process.Context, path_ptr: usize, path_len: usize) void {
    const path = @as([*]u8, @ptrFromInt(path_ptr))[0..path_len];

    const result: *isize = @ptrCast(&context.rax);

    result.* = 0;

    tmpfs.makeDirectory("/", path) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
        error.NotFound => result.* = -1,
        error.NotDirectory => result.* = -2,
        error.PathNotAbsolute => result.* = -3,
    };
}

pub fn mkfile(context: *arch.cpu.process.Context, path_ptr: usize, path_len: usize) void {
    const path = @as([*]u8, @ptrFromInt(path_ptr))[0..path_len];

    const result: *isize = @ptrCast(&context.rax);

    result.* = 0;

    const empty_buffer: [0]u8 = undefined;
    var empty_stream = std.io.fixedBufferStream(&empty_buffer);

    tmpfs.makeFile("/", path, 0, empty_stream.reader()) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
        error.NotFound => result.* = -1,
        error.NotDirectory => result.* = -2,
        error.PathNotAbsolute => result.* = -3,
    };
}
