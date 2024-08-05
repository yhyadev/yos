//! Spawn Point (also called Source File)
//!
//! This is where the operating system starts the initialization

const std = @import("std");
const limine = @import("limine");

// Bring Your Own OS
pub const os = @import("os.zig");

// It is important to be public for @panic builtin and std.debug.print to call it
pub const panic = crash.panic;

const acpi = @import("acpi.zig");
const arch = @import("arch.zig");
const crash = @import("crash.zig");
const initrd = @import("initrd.zig");
const memory = @import("memory.zig");
const screen = @import("screen.zig");
const smp = @import("smp.zig");
const tty = @import("tty.zig");
const tarfs = @import("fs/tarfs.zig");
const vfs = @import("fs/vfs.zig");
const ps2 = @import("drivers/keyboard/ps2.zig");

export var base_revision: limine.BaseRevision = .{ .revision = 2 };

/// The entry point that limine bootloader loads
pub export fn _start() noreturn {
    // Check if limine understands our base revision
    if (!base_revision.is_supported()) {
        arch.cpu.hang();
    }

    // Initialize symmetric multiprocessing and go to the first stage
    smp.init(stage1);
}

/// Did the first core finish first stage?
var stage1_done = false;

/// First stage: Initialize features
fn stage1() noreturn {
    arch.cpu.interrupts.disable();

    const core_id = smp.getCoreId();

    if (core_id == 0) {
        // Initialize screen framebuffers
        screen.init();

        // Initialize teletype emulation
        tty.init();

        // Initialize memory allocation
        memory.init();

        // After memory allocation is initialized, we now can use the page allocator
        const allocator = std.heap.page_allocator;

        // Initialize virtual file system
        vfs.init(allocator) catch |err| switch (err) {
            error.OutOfMemory => @panic("out of memory"),
        };

        // Initialize tar file system
        tarfs.init(allocator) catch |err| switch (err) {
            error.OutOfMemory => @panic("out of memory"),
        };

        // Initialize the init ramdisk
        initrd.init();

        // Initialize power management
        acpi.init();

        // Initialize architecture-specific features (ioapic, lapic, idt, etc...)
        arch.init();

        // Initialize ps/2 keyboard
        ps2.init();

        stage1_done = true;
    } else {
        while (!stage1_done) {}

        // Initialize architecture-specific features (ioapic, lapic, idt, etc...)
        arch.init();
    }

    stage2();
}

/// Second stage: Join user-space and start scheduling root applications
fn stage2() noreturn {
    arch.cpu.interrupts.enable();

    arch.cpu.hang();
}
