const std = @import("std");
const limine = @import("limine");

// Bring Your Own OS
pub const os = @import("os.zig");

// It is important to be public for @panic builtin and std.debug.print to call it
pub const panic = crash.panic;

const acpi = @import("acpi.zig");
const arch = @import("arch.zig");
const crash = @import("crash.zig");
const memory = @import("memory.zig");
const screen = @import("screen.zig");
const smp = @import("smp.zig");
const tty = @import("tty.zig");
const ps2 = @import("drivers/keyboard/ps2.zig");

export var base_revision: limine.BaseRevision = .{ .revision = 2 };

/// The entry point that limine bootloader loads
pub export fn _start() noreturn {
    // Check if limine understands our base revision
    if (!base_revision.is_supported()) {
        arch.hang();
    }

    // Initialize symmetric multiprocessing and go to the first stage
    smp.init(stage1);
}

/// First stage: Initialize features
fn stage1() noreturn {
    arch.cpu.interrupts.disable();

    // Initialize screen drawing
    screen.init();

    // Initialize teletype emulation on screen
    tty.init();

    // Initialize memory allocation
    memory.init();

    // Initialize power management
    acpi.init();

    // Initialize architecture-specific features (ioapic, lapic, idt, etc...)
    arch.init();

    // Initialize ps/2 keyboard
    ps2.init();

    stage2();
}

/// Second stage: Run the scheduler and join user-space
fn stage2() noreturn {
    arch.cpu.interrupts.enable();

    arch.hang();
}
