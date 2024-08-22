const std = @import("std");
const abi = @import("abi");

const arch = @import("arch.zig");
const higher_half = @import("higher_half.zig");
const scheduler = @import("scheduler.zig");
const screen = @import("screen.zig");
const stream = @import("stream.zig");
const tmpfs = @import("fs/tmpfs.zig");
const vfs = @import("fs/vfs.zig");

const user_allocator = @import("memory.zig").user_allocator;

pub fn write(context: *arch.cpu.process.Context, fd: usize, offset: usize, buffer_ptr: usize, buffer_len: usize) void {
    if (buffer_len == 0) {
        context.rax = 0;

        return;
    }

    const buffer = @as([*]const u8, @ptrFromInt(buffer_ptr))[0..buffer_len];

    const process = scheduler.maybe_process.?;

    context.rax = process.writeFile(fd, offset, buffer);
}

pub fn read(context: *arch.cpu.process.Context, fd: usize, offset: usize, buffer_ptr: usize, buffer_len: usize) void {
    if (buffer_len == 0) {
        context.rax = 0;

        return;
    }

    const buffer = @as([*]u8, @ptrFromInt(buffer_ptr))[0..buffer_len];

    const process = scheduler.maybe_process.?;

    context.rax = process.readFile(fd, offset, buffer);
}

pub fn readdir(context: *arch.cpu.process.Context, fd: usize, offset: usize, buffer_ptr: usize, buffer_len: usize) void {
    if (buffer_len == 0) {
        context.rax = 0;

        return;
    }

    const process = scheduler.maybe_process.?;

    const kernel_allocator = process.arena.allocator();

    const dir_entry_buffer = @as([*]abi.DirEntry, @ptrFromInt(buffer_ptr))[0..buffer_len];

    const node_buffer = kernel_allocator.alloc(*vfs.FileSystem.Node, buffer_len) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
    };

    defer kernel_allocator.free(node_buffer);

    context.rax = process.readDir(fd, offset, node_buffer);

    if (context.rax == 0) return;

    for (node_buffer, dir_entry_buffer) |node, *dir_entry| {
        dir_entry.* = .{
            .name = user_allocator.dupeZ(u8, node.name) catch |err| switch (err) {
                error.OutOfMemory => @panic("out of memory"),
            },

            .tag = switch (node.tag) {
                .file => .file,
                .directory => .directory,
            },
        };
    }
}

pub fn open(context: *arch.cpu.process.Context, path_ptr: usize, path_len: usize) void {
    const path = if (path_len != 0) @as([*]const u8, @ptrFromInt(path_ptr))[0..path_len] else "";

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

pub fn execve(context: *arch.cpu.process.Context, argv_ptr: usize, argv_len: usize, envp_ptr: usize, envp_len: usize) void {
    const argv: []const [*:0]const u8 = if (argv_len != 0) @as([*]const [*:0]const u8, @ptrFromInt(argv_ptr))[0..argv_len] else &.{};
    const envp: []const [*:0]const u8 = if (envp_len != 0) @as([*]const [*:0]const u8, @ptrFromInt(envp_ptr))[0..envp_len] else &.{};

    const result: *isize = @ptrCast(&context.rax);

    result.* = 0;

    scheduler.execve(context, argv, envp) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
        error.NotFound => result.* = -1,
        error.NotDirectory => result.* = -2,
        error.PathNotAbsolute => result.* = -3,
        error.BadElf => result.* = -4,
        error.BadEnvPair => result.* = -5,
    };
}

var maybe_framebuffer_virtual_address: ?usize = null;

pub fn getframebuffer(context: *arch.cpu.process.Context, width_ptr: usize, height_ptr: usize) void {
    @as(*usize, @ptrFromInt(width_ptr)).* = screen.framebuffer.width;
    @as(*usize, @ptrFromInt(height_ptr)).* = screen.framebuffer.height;

    const page_table = arch.paging.getActivePageTable();

    if (maybe_framebuffer_virtual_address) |framebuffer_virtual_address| {
        context.rax = framebuffer_virtual_address;
    } else {
        const framebuffer_physical_address = page_table.physicalFromVirtual(@intFromPtr(screen.framebuffer.address)).?;

        context.rax = searchAndMap(0, framebuffer_physical_address, screen.framebuffer.width * screen.framebuffer.height * 4, 0x2);

        if (context.rax != 0) {
            maybe_framebuffer_virtual_address = context.rax;
        }
    }
}

pub fn getargv(context: *arch.cpu.process.Context, len_ptr: usize) void {
    const process = scheduler.maybe_process.?;

    @as(*usize, @ptrFromInt(len_ptr)).* = process.argv.len;

    context.rax = @intFromPtr(process.argv.ptr);
}

pub fn putenv(context: *arch.cpu.process.Context, env_pair_ptr: usize, env_pair_len: usize) void {
    const env_pair = if (env_pair_len != 0) @as([*]const u8, @ptrFromInt(env_pair_ptr))[0..env_pair_len] else "";

    const process = scheduler.maybe_process.?;

    const result: *isize = @ptrCast(&context.rax);

    result.* = 0;

    process.putEnvPair(env_pair) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
        error.BadEnvPair => result.* = -1,
    };
}

pub fn getenv(context: *arch.cpu.process.Context, env_key_ptr: usize, env_key_len: usize, env_value_len_ptr: usize) void {
    const env_key = if (env_key_len != 0) @as([*]const u8, @ptrFromInt(env_key_ptr))[0..env_key_len] else "";

    const process = scheduler.maybe_process.?;

    context.rax = 0;

    const env_value = process.env.get(env_key) orelse return;

    @as(*usize, @ptrFromInt(env_value_len_ptr)).* = env_value.len;

    context.rax = @intFromPtr(env_value.ptr);
}

pub fn mmap(context: *arch.cpu.process.Context, virtual_address_hint: usize, bytes_len: usize, protection: usize, _: usize) void {
    const process = scheduler.maybe_process.?;

    const kernel_allocator = process.arena.allocator();

    const bytes = kernel_allocator.alignedAlloc(u8, std.mem.page_size, bytes_len) catch {
        context.rax = 0;

        return;
    };

    const physical_address = process.page_table.physicalFromVirtual(@intFromPtr(bytes.ptr)).?;

    context.rax = searchAndMap(virtual_address_hint, physical_address, bytes_len, protection);
}

fn searchAndMap(virtual_address_hint: usize, physical_address: usize, bytes_len: usize, protection: usize) usize {
    const process = scheduler.maybe_process.?;

    const page_count = std.math.divCeil(usize, bytes_len, std.mem.page_size) catch unreachable;

    const kernel_allocator = process.arena.allocator();

    const min_virtual_address = 0x10000;

    var virtual_address: usize = min_virtual_address;

    while (virtual_address < std.math.maxInt(usize)) : (virtual_address += std.mem.page_size) {
        if (!process.page_table.mapped(virtual_address)) retry: {
            for (1..page_count) |i| {
                if (process.page_table.mapped(virtual_address + i * std.mem.page_size)) {
                    virtual_address += i * std.mem.page_size;

                    break :retry;
                }
            }

            for (0..page_count) |i| {
                const offsetted_virtual_address = virtual_address + i * std.mem.page_size;
                const offsetted_physical_address = physical_address + i * std.mem.page_size;

                process.page_table.map(
                    kernel_allocator,
                    offsetted_virtual_address,
                    offsetted_physical_address,
                    .{
                        .user = true,
                        .global = false,
                        .writable = (protection & 0x2) != 0,
                        .executable = (protection & 0x4) != 0,
                    },
                ) catch {
                    return 0;
                };
            }

            return virtual_address;
        }

        if (virtual_address == min_virtual_address and virtual_address_hint != 0) {
            virtual_address = std.mem.alignForward(usize, virtual_address_hint, std.mem.page_size) - std.mem.page_size;
        }
    }

    return 0;
}

pub fn munmap(_: *arch.cpu.process.Context, bytes_ptr: usize, bytes_len: usize) void {
    const process = scheduler.maybe_process.?;

    const kernel_allocator = process.arena.allocator();

    const page_count = std.math.divCeil(usize, bytes_len, std.mem.page_size) catch unreachable;

    kernel_allocator.free(@as([*]u8, @ptrFromInt(higher_half.virtualFromPhysical(process.page_table.physicalFromVirtual(bytes_ptr).?)))[0..bytes_len]);

    for (0..page_count) |i| {
        process.page_table.unmap(bytes_ptr + i * std.mem.page_size);
    }
}

pub fn mkdir(context: *arch.cpu.process.Context, path_ptr: usize, path_len: usize) void {
    const path = if (path_len != 0) @as([*]const u8, @ptrFromInt(path_ptr))[0..path_len] else "";

    const process = scheduler.maybe_process.?;

    const result: *isize = @ptrCast(&context.rax);

    result.* = 0;

    tmpfs.makeDirectory(process.env.get("PWD").?, path) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
        error.NotFound => result.* = -1,
        error.NotDirectory => result.* = -2,
        error.PathNotAbsolute => result.* = -3,
        error.AlreadyExists => result.* = -4,
    };
}

pub fn mkfile(context: *arch.cpu.process.Context, path_ptr: usize, path_len: usize) void {
    const path = if (path_len != 0) @as([*]const u8, @ptrFromInt(path_ptr))[0..path_len] else "";

    const process = scheduler.maybe_process.?;

    const result: *isize = @ptrCast(&context.rax);

    result.* = 0;

    const empty_buffer: [0]u8 = undefined;
    var empty_stream = std.io.fixedBufferStream(&empty_buffer);

    tmpfs.makeFile(process.env.get("PWD").?, path, 0, empty_stream.reader()) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
        error.NotFound => result.* = -1,
        error.NotDirectory => result.* = -2,
        error.PathNotAbsolute => result.* = -3,
        error.AlreadyExists => result.* = -4,
    };
}
