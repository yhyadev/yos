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
        if (stream.keys.poll()) |key| {
            result.* = @as(u8, @bitCast(key));
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
    const color: screen.Color = @bitCast(color_32);

    screen.get(x, y).* = color;
}

pub fn scrget(context: *arch.cpu.process.Context, x: usize, y: usize) void {
    const result: *screen.Color = @ptrCast(&context.rax);

    result.* = screen.get(x, y).*;
}

pub fn scrwidth(context: *arch.cpu.process.Context) void {
    context.rax = screen.framebuffer.width;
}

pub fn scrheight(context: *arch.cpu.process.Context) void {
    context.rax = screen.framebuffer.height;
}
