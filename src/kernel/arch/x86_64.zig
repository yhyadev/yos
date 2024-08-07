pub const cpu = @import("x86_64/cpu.zig");
pub const gdt = @import("x86_64/gdt.zig");
pub const idt = @import("x86_64/idt.zig");
pub const ioapic = @import("x86_64/ioapic.zig");
pub const lapic = @import("x86_64/lapic.zig");
pub const paging = @import("x86_64/paging.zig");
pub const pic = @import("x86_64/pic.zig");
pub const syscall = @import("x86_64/syscall.zig");

pub fn init() void {
    gdt.init();
    idt.init();
    paging.init();
    pic.disable();
    ioapic.init();
    lapic.init();
    syscall.init();
}
