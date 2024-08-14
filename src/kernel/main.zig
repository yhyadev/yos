//! Spawn Point (also called Source File)
//!
//! This is where the operating system starts the initialization

const std = @import("std");
const limine = @import("limine");

pub const os = @import("os.zig");

pub const panic = crash.panic;

const acpi = @import("acpi.zig");
const arch = @import("arch.zig");
const console = @import("console.zig");
const crash = @import("crash.zig");
const higher_half = @import("higher_half.zig");
const initrd = @import("initrd.zig");
const memory = @import("memory.zig");
const scheduler = @import("scheduler.zig");
const screen = @import("screen.zig");
const smp = @import("smp.zig");
const devfs = @import("fs/devfs.zig");
const tarfs = @import("fs/tarfs.zig");
const vfs = @import("fs/vfs.zig");
const ps2 = @import("drivers/keyboard/ps2.zig");

export var base_revision: limine.BaseRevision = .{ .revision = 2 };

/// The entry point that limine bootloader loads
pub export fn _start() noreturn {
    // Check if limine understands our base revision
    if (!base_revision.is_supported()) {
        arch.cpu.process.hang();
    }

    // Initialize screen framebuffers
    screen.init();

    // Initialize console
    console.init();

    // Initialize symmetric multiprocessing and go to the first stage
    smp.init(&stage1);
}

/// Did the first core finish first stage?
var stage1_done = false;

/// First stage: Initialize features
fn stage1() noreturn {
    arch.cpu.interrupts.disable();

    const core_id = arch.cpu.core.Info.read().id;

    if (core_id == 0) {
        // Initialize information about our higher half kernel
        higher_half.init();

        // Initialize memory allocation
        memory.init();

        // After memory allocation is initialized, we now can use the page allocator
        const allocator = std.heap.page_allocator;

        // Initialize virtual file system
        vfs.init(allocator);

        // Initialize tar file system
        tarfs.init(allocator) catch |err| switch (err) {
            error.OutOfMemory => @panic("out of memory"),
        };

        // Initialize device file system
        devfs.init(allocator) catch |err| switch (err) {
            error.OutOfMemory => @panic("out of memory"),

            else => unreachable,
        };

        // Initialize the initial ramdisk
        initrd.init();

        // Initialize scheduler
        scheduler.init(allocator);

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

/// Second stage: Start scheduling applications
fn stage2() noreturn {
    arch.cpu.interrupts.enable();

    const core_id = arch.cpu.core.Info.read().id;

    if (core_id == 0) {
        // Load the initial process
        scheduler.setInitialProcess("/usr/bin/init") catch |err| switch (err) {
            error.OutOfMemory => @panic("out of memory"),
            error.NotFound => @panic("the initial process file is not found in initial ramdisk"),
            error.NotDirectory => @panic("the initial process path is incorrect, caused by a component that is not directory"),
            error.BadElf => @panic("the initial process file is an incorrect elf"),
            error.PathNotAbsolute => unreachable,
        };

        // Start scheduling, which passes control to user-space initial process
        scheduler.start();
    }

    arch.cpu.process.hang();
}
