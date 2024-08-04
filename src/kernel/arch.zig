const builtin = @import("builtin");

pub const target_cpu = builtin.cpu.arch;

const system = switch (target_cpu) {
    .x86_64 => @import("arch/x86_64.zig"),

    else => @compileError("Target CPU is not supported"),
};

pub const cpu = system.cpu;

pub const ioapic = switch (target_cpu) {
    .x86_64 => system.ioapic,

    else => {},
};

pub fn init() void {
    system.init();
}
