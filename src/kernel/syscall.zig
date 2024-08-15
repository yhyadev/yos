const std = @import("std");
const abi = @import("abi");

const arch = @import("arch.zig");
const scheduler = @import("scheduler.zig");
const screen = @import("screen.zig");
const stream = @import("stream.zig");

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

pub fn execv(context: *arch.cpu.process.Context, argv_ptr: usize, argv_len: usize) void {
    const argv = @as([*]const [*:0]const u8, @ptrFromInt(argv_ptr))[0..argv_len];

    const result: *isize = @ptrCast(&context.rax);

    result.* = 0;

    scheduler.execv(context, argv) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
        error.NotFound => result.* = -1,
        error.NotDirectory => result.* = -2,
        error.PathNotAbsolute => result.* = -3,
        error.BadElf => result.* = -4,
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

const mmap_min_address = 0x10000;

pub fn mmap(context: *arch.cpu.process.Context, virtual_address_hint: usize, bytes_len: usize, protection: usize, _: usize) void {
    const page_table = arch.paging.getActivePageTable();

    const page_count = std.math.divCeil(usize, bytes_len, std.mem.page_size) catch unreachable;

    context.rax = 0;

    const bytes = std.heap.page_allocator.alloc(u8, bytes_len) catch return;

    const physical_address = page_table.physicalFromVirtual(@intFromPtr(bytes.ptr)).?;

    var virtual_address: usize = mmap_min_address;

    while (virtual_address < std.math.maxInt(usize)) : (virtual_address += std.mem.page_size) {
        if (page_table.physicalFromVirtual(virtual_address) == null) retry: {
            for (1..page_count) |j| {
                if (page_table.physicalFromVirtual(virtual_address + j * std.mem.page_size) != null) {
                    virtual_address += j * std.mem.page_size;

                    break :retry;
                }
            }

            for (0..page_count) |j| {
                const offsetted_virtual_address = virtual_address + j * std.mem.page_size;
                const offsetted_physical_address = physical_address + j * std.mem.page_size;

                page_table.map(
                    std.heap.page_allocator,
                    offsetted_virtual_address,
                    offsetted_physical_address,
                    .{
                        .user = true,
                        .global = false,
                        .writable = (protection | 2) != 0,
                        .executable = (protection | 4) != 0,
                    },
                ) catch {
                    return;
                };
            }

            context.rax = virtual_address;

            return;
        }

        if (virtual_address == mmap_min_address and virtual_address_hint != 0) {
            virtual_address = std.mem.alignForward(usize, virtual_address_hint, std.mem.page_size) - std.mem.page_size;
        }
    }
}

pub fn munmap(_: *arch.cpu.process.Context, bytes_ptr: usize, bytes_len: usize) void {
    const page_table = arch.paging.getActivePageTable();

    const page_count = std.math.divCeil(usize, bytes_len, std.mem.page_size) catch unreachable;

    std.heap.page_allocator.free(@as([*]u8, @ptrFromInt(arch.paging.virtualFromPhysical(page_table.physicalFromVirtual(bytes_ptr).?)))[0..bytes_len]);

    for (0..page_count) |i| {
        page_table.unmap(bytes_ptr + i * std.mem.page_size);
    }
}
