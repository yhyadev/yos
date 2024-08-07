const std = @import("std");

const cpu = @import("cpu.zig");

pub fn init() void {
    cpu.registers.ModelSpecific.write(.star, (0x8 << 32) | ((0x18 - 0x8) << 48));
    cpu.registers.ModelSpecific.write(.lstar, @intFromPtr(&syscallEntry));
    cpu.registers.ModelSpecific.write(.efer, cpu.registers.ModelSpecific.read(.efer) | 1);
    cpu.registers.ModelSpecific.write(.sf_mask, 0b1111110111111111010101);
}

fn syscallEntry() callconv(.Naked) void {
    asm volatile (
        \\sysretq
    );
}
