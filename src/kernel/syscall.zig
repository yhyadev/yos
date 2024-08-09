const arch = @import("arch.zig");
const scheduler = @import("scheduler.zig");
const tty = @import("tty.zig");

pub fn exit(context: *arch.cpu.process.Context, _: usize) void {
    const process = scheduler.maybe_process.?;

    scheduler.kill(process.id);

    scheduler.reschedule(context) catch @panic("out of memory");
}

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

        else => -@as(isize, @intCast(@intFromError(err))),
    };
}

pub fn close(context: *arch.cpu.process.Context, fd: usize) void {
    const process = scheduler.maybe_process.?;

    const result: *isize = @ptrCast(&context.rax);

    result.* = 0;

    process.closeFile(fd) catch |err| {
        result.* = -@as(isize, @intCast(@intFromError(err)));
    };
}
