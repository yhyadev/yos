const std = @import("std");
const limine = @import("limine");

const arch = @import("arch.zig");
const screen = @import("screen.zig");
const tty = @import("tty.zig");

export var base_revision: limine.BaseRevision = .{ .revision = 2 };

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    arch.cpu.interrupts.disable();

    tty.print("\npanic: {s}\n", .{message});

    arch.hang();
}

export fn _start() noreturn {
    arch.cpu.interrupts.disable();

    // Check if limine understands our base revision
    if (!base_revision.is_supported()) {
        arch.hang();
    }

    screen.init();

    tty.init();

    tty.print("init: architecture specific features\n", .{});

    arch.init();

    tty.print("init: all features initialized..\n", .{});

    arch.cpu.interrupts.enable();

    arch.hang();
}
