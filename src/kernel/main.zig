const std = @import("std");
const limine = @import("limine");

pub const os = @import("os.zig");

const arch = @import("arch.zig");
const memory = @import("memory.zig");
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

    tty.print("init: initialize memory allocation feature\n", .{});
    memory.init();

    tty.print("init: initialize architecture specific features\n", .{});
    arch.init();

    tty.print("init: all features are initialized\n", .{});

    arch.cpu.interrupts.enable();

    arch.hang();
}
