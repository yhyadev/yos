const cpu = @import("cpu.zig");

pub const master_command_port = 0x20;
pub const master_data_port = master_command_port + 0x01;

pub const slave_command_port = 0xA0;
pub const slave_data_port = slave_command_port + 0x01;

pub const master_offset = master_command_port;
pub const slave_offset = master_offset + 8;

pub const timer_interrupt = master_offset;
pub const keyboard_interrupt = timer_interrupt + 1;

pub const icw1_icw4 = 0x01;
pub const icw1_single = 0x02;
pub const icw1_interval4 = 0x04;
pub const icw1_level = 0x08;
pub const icw1_init = 0x10;

pub const icw4_8086 = 0x01;
pub const icw4_auto = 0x02;
pub const icw4_buf_slave = 0x08;
pub const icw4_buf_master = 0x0C;
pub const icw4_sfnm = 0x10;

pub const eoi = 0x20;

// Quote from complete-pic rust crate:
//       "We need to add a delay between writes to our PICs, especially on
//       older motherboards. But we don't necessarily have any kind of
//       timers yet, because most of them require interrupts. Various
//       older versions of Linux and other PC operating systems have
//       worked around this by writing garbage data to port 0x80, which
//       allegedly takes long enough to make everything work on most
//       hardware."
fn wait() void {
    cpu.io.outb(0x80, 0);
}

pub fn init() void {
    const master_data_mask = cpu.io.inb(master_data_port);
    const slave_data_mask = cpu.io.inb(slave_data_port);

    // Start the initialization sequence (in cascade mode)
    cpu.io.outb(master_command_port, icw1_init | icw1_icw4);
    wait();

    cpu.io.outb(slave_command_port, icw1_init | icw1_icw4);
    wait();

    // ICW2: Master PIC vector offset
    cpu.io.outb(master_data_port, master_offset);
    wait();

    // ICW2: Slave PIC vector offset
    cpu.io.outb(slave_data_port, slave_offset);
    wait();

    // ICW3: tell Master PIC that there is a slave PIC at IRQ2 (0000 0100)
    cpu.io.outb(master_data_port, 4);
    wait();

    // ICW3: tell Slave PIC its cascade identity (0000 0010)
    cpu.io.outb(slave_data_port, 2);
    wait();

    // ICW4: have the PICs use 8086 mode (and not 8080 mode)
    cpu.io.outb(master_data_port, icw4_8086);
    wait();

    cpu.io.outb(slave_data_port, icw4_8086);
    wait();

    cpu.io.outb(master_data_port, master_data_mask);
    cpu.io.outb(slave_data_port, slave_data_mask);
}

pub fn disable() void {
    cpu.io.outb(master_data_port, 0xff);
    cpu.io.outb(slave_data_port, 0xff);
}

pub fn notifyEndOfInterrupt(irq: u8) void {
    if (irq >= 8) cpu.io.outb(slave_command_port, eoi);
    cpu.io.outb(master_command_port, eoi);
}

pub fn set_mask(irq: u8) void {
    var port: u16 = undefined;
    var modified_irq: u3 = undefined;

    if (irq < 8) {
        port = master_data_port;
        modified_irq = @truncate(irq);
    } else {
        port = master_command_port;
        modified_irq = @truncate(irq - 8);
    }

    cpu.io.outb(port, cpu.io.inb(port) | (@as(u8, 1) << modified_irq));
}

pub fn clear_mask(irq: u8) void {
    var port: u16 = undefined;
    var modified_irq: u3 = undefined;

    if (irq < 8) {
        port = master_data_port;
        modified_irq = @truncate(irq);
    } else {
        port = master_command_port;
        modified_irq = @truncate(irq - 8);
    }

    cpu.io.outb(port, cpu.io.inb(port) & ~(@as(u8, 1) << modified_irq));
}
