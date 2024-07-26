const std = @import("std");
const limine = @import("limine");

const arch = @import("arch.zig");
const screen = @import("screen.zig");
const tty = @import("tty.zig");

pub export var base_revision: limine.BaseRevision = .{ .revision = 2 };

pub export var framebuffer_request: limine.FramebufferRequest = .{};

export fn _start() noreturn {
    // Check if limine understands our base revision
    if (!base_revision.is_supported()) {
        arch.hang();
    }

    arch.cpu.cli();

    screen.init(framebuffer_request.response);

    tty.init();

    tty.print("init: architecture specific features\n", .{});

    arch.init();

    tty.print("init: all features initialized..\n", .{});

    arch.cpu.sti();

    arch.hang();
}

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, return_address: ?usize) noreturn {
    _ = stack_trace;
    _ = return_address;

    // Clear anything on the screen before trying to print
    tty.clear();

    // TODO: Try to print the stack trace
    tty.print("panic: {s}\n", .{message});

    arch.hang();
}
