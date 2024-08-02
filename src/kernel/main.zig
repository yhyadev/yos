const std = @import("std");
const limine = @import("limine");

// Bring Your Own OS feature
pub const os = @import("os.zig");

// It is important to be public for @panic builtin and std.debug.print to call it
pub const panic = crash.panic;

const acpi = @import("acpi.zig");
const arch = @import("arch.zig");
const crash = @import("crash.zig");
const memory = @import("memory.zig");
const screen = @import("screen.zig");
const tty = @import("tty.zig");

export var base_revision: limine.BaseRevision = .{ .revision = 2 };

/// The entry point that limine bootloader loads
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

    tty.print("init: initialize power management feature\n", .{});
    acpi.init();

    tty.print("init: initialize architecture specific features\n", .{});
    arch.init();

    tty.print("init: all features are initialized\n", .{});

    arch.cpu.interrupts.enable();

    arch.hang();
}
