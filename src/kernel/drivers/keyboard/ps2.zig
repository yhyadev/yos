//! PS/2 Keyboard
//!
//! An implementation of the PS/2 Keyboard

const arch = @import("../../arch.zig");
const smp = @import("../../smp.zig");
const stream = @import("../../stream.zig");

const Keyboard = @import("ps2/Keyboard.zig");

pub var keyboard: Keyboard = .{};

var initialized = false;

const command_port = 0x64;
const data_port = 0x60;

const disable_first_port = 0xAD;
const enable_first_port = disable_first_port + 0x01;
const disable_second_port = 0xA7;
const enable_second_port = disable_second_port + 0x01;

/// Disable the communication of the PS/2 Keyboard
pub fn enable() void {
    arch.cpu.io.outb(command_port, enable_first_port);
    arch.cpu.io.outb(command_port, enable_second_port);
}

/// Disable the communication of the PS/2 Keyboard
pub fn disable() void {
    arch.cpu.io.outb(command_port, disable_first_port);
    arch.cpu.io.outb(command_port, disable_second_port);
}

/// Called when the PS/2 Keyboard makes an interrupt
fn interrupt(_: *arch.cpu.process.Context) callconv(.C) void {
    defer arch.cpu.interrupts.end();

    const scancode = arch.cpu.io.inb(data_port);

    if (initialized) {
        if (keyboard.map(scancode)) |key| {
            stream.keys.append(key);
        }
    }
}

pub fn init() void {
    disable();

    // Setup the interrupt handler for the PS/2 Keyboard
    arch.cpu.interrupts.handle(1, interrupt);

    // On x86 CPUs remove the mask of PS/2 Keyboard interrupt and set where the interrupt handler is
    if (arch.target.isX86()) {
        var red_entry = arch.ioapic.readRedEntry(1);
        red_entry.mask = false;
        red_entry.destination = @truncate(smp.bootstrap_lapic_id);
        red_entry.vector = arch.cpu.interrupts.offset(1);

        arch.ioapic.writeRedEntry(1, red_entry);
    }

    enable();

    initialized = true;
}
