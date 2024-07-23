const std = @import("std");
const limine = @import("limine");

const arch = @import("arch.zig");
const screen = @import("screen.zig");
const tty = @import("tty.zig");

pub export var base_revision: limine.BaseRevision = .{ .revision = 2 };

pub export var stack_size_request: limine.StackSizeRequest = .{ .stack_size = 16 * 1024 };

pub export var framebuffer_request: limine.FramebufferRequest = .{};

export fn _start() callconv(.C) noreturn {
    // Check if limine understands our base revision
    if (!base_revision.is_supported()) {
        arch.hang();
    }

    // Initialize the screen before printing
    screen.init(framebuffer_request.response);

    // Initialize the state of the tty
    tty.init();

    // Print to test if the printing works
    tty.print("-- Welcome to The Y Operating System --\n", .{});
    tty.print("-- Welcome to The Y Operating System ---- Welcome to The Y Operating System ---- Welcome to The Y Operating System ---- Welcome to The Y Operating System ---- Welcome to The Y Operating System ---- Welcome to The Y Operating System ---- Welcome to The Y Operating System ---- Welcome to The Y Operating System --\n", .{});

    // The kernel should not return no matter what
    arch.hang();
}

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, return_address: ?usize) noreturn {
    _ = stack_trace;
    _ = return_address;

    // Clear anything on the screen before trying to print
    tty.clear();

    // TODO: Try to print the stack trace
    tty.print("kernel panic occured: {s}\n", .{message});

    arch.hang();
}
