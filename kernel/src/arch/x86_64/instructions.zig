/// Clear the interrupt flag (IF)
pub inline fn cli() void {
    asm volatile ("cli");
}

/// Wait for another interrupt until the next iteration, this usually used to put the CPU to sleep
pub inline fn hlt() void {
    asm volatile ("hlt");
}
