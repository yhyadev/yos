const GlobalDescriptorTable = @import("gdt.zig").GlobalDescriptorTable;
const InterruptDescriptorTable = @import("idt.zig").InterruptDescriptorTable;

/// Disable interrupts
pub inline fn cli() void {
    asm volatile ("cli");
}

/// Enable interrupts
pub inline fn sti() void {
    asm volatile ("sti");
}

/// Wait for another interrupt until the next iteration, this usually used to put the CPU to sleep
pub inline fn hlt() void {
    asm volatile ("hlt");
}

/// Invoke breakpoint interrupt
pub inline fn int3() void {
    asm volatile ("int $3");
}

/// Get the code segment
pub inline fn cs() u16 {
    return asm volatile ("mov %cs, %[ret]"
        : [ret] "={rax}" (-> u16),
    );
}

/// Load the GDT
pub inline fn lgdt(gdtr: *const GlobalDescriptorTable.Register) void {
    asm volatile ("lgdt (%[ptr])"
        :
        : [ptr] "{rax}" (@intFromPtr(gdtr)),
    );
}

/// Reload Segments
pub noinline fn reloadSegments() void {
    asm volatile (
        \\pushq $0x08
        \\pushq $reloadCodeSegment
        \\lretq
        \\
        \\reloadCodeSegment:
        \\  mov $0x10, %ax
        \\  mov %ax, %es
        \\  mov %ax, %ss
        \\  mov %ax, %ds
        \\  mov %ax, %fs
        \\  mov %ax, %gs
    );
}

/// Load the IDT
pub inline fn lidt(idtr: *const InterruptDescriptorTable.Register) void {
    asm volatile ("lidt (%[ptr])"
        :
        : [ptr] "{rax}" (idtr),
    );
}

/// Load the Task Register (Which is a segment selector of the TSS in the GDT)
pub inline fn ltr(tr: u16) void {
    asm volatile ("ltr %[reg]"
        :
        : [reg] "{rax}" (tr),
    );
}
