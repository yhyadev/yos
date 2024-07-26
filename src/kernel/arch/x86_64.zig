pub const cpu = @import("x86_64/cpu.zig");
pub const gdt = @import("x86_64/gdt.zig");
pub const idt = @import("x86_64/idt.zig");

pub fn init() void {
    gdt.init();
    idt.init();
}