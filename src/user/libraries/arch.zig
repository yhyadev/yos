const builtin = @import("builtin");

pub const target = builtin.cpu.arch;

const system = switch (target) {
    .x86_64 => @import("arch/x86_64.zig"),

    else => struct {},
};

pub const cpu = system.cpu;
