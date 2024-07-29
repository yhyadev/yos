//! This is not for the playstation 2, it's a wrapper around PS/2 Keyboard functionalities (https://wiki.osdev.org/PS/2_Keyboard)

const arch = @import("../../arch.zig");
const stream = @import("../../stream.zig");

pub const Key = @import("Key.zig");

const command_port = 0x64;
const data_port = 0x60;

pub fn appendToStream() void {
    const scancode = arch.cpu.io.inb(data_port);
    stream.scancodes.append(scancode);
}
