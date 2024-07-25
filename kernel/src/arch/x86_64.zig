pub const gdt = @import("x86_64/gdt.zig");
pub const idt = @import("x86_64/idt.zig");
pub const instructions = @import("x86_64/instructions.zig");

pub fn init() void {
    gdt.init();
    idt.init();
}
