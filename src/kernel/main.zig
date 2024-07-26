const std = @import("std");
const limine = @import("limine");

const arch = @import("arch.zig");
const screen = @import("screen.zig");
const tty = @import("tty.zig");

pub export var base_revision: limine.BaseRevision = .{ .revision = 2 };

pub export var framebuffer_request: limine.FramebufferRequest = .{};

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    // Clear anything on the screen before trying to print the panic, this is usually because the user may be in a gui and not the tty
    tty.clear();

    tty.print("panic: {s}\n", .{message});

    arch.hang();
}

export fn _start() noreturn {
    // Check if limine understands our base revision
    if (!base_revision.is_supported()) {
        arch.hang();
    }

    arch.cpu.cli();

    screen.init(framebuffer_request.response);

    tty.init();

    tty.print("init: architecture specific features\n", .{});

    {
        @panic("hey");
    }

    arch.init();

    tty.print("init: all features initialized..\n", .{});

    arch.cpu.sti();

    arch.hang();
}
