const arch = @import("../../arch.zig");
const smp = @import("../../smp.zig");
const stream = @import("../../stream.zig");

pub const Keyboard = @import("ps2/Keyboard.zig");

var initialized = false;

const command_port = 0x64;
const data_port = 0x60;

const disable_first_port = 0xAD;
const enable_first_port = disable_first_port + 0x01;
const disable_second_port = 0xA7;
const enable_second_port = disable_second_port + 0x01;

pub fn interrupt() void {
    const scancode = arch.cpu.io.inb(data_port);

    if (initialized) {
        stream.scancodes.append(scancode);
    }
}

pub fn enable() void {
    arch.cpu.io.outb(command_port, enable_first_port);
    arch.cpu.io.outb(command_port, enable_second_port);
}

pub fn disable() void {
    arch.cpu.io.outb(command_port, disable_first_port);
    arch.cpu.io.outb(command_port, disable_second_port);
}

pub fn init() void {
    disable();

    arch.cpu.interrupts.handle(1, interrupt);

    if (arch.target_cpu.isX86()) {
        var red_entry = arch.ioapic.readRedEntry(1);
        red_entry.mask = false;
        red_entry.destination = @truncate(smp.bootstrap_lapic_id);
        red_entry.vector = 1 + 32;

        arch.ioapic.writeRedEntry(1, red_entry);
    }

    enable();

    initialized = true;
}
