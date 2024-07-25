const builtin = @import("builtin");

const target_arch = builtin.cpu.arch;

const system = switch (target_arch) {
    .x86_64 => @import("arch/x86_64.zig"),
    else => @compileError("Target CPU is not supported"),
};

pub const instructions = system.instructions;

pub fn init() void {
    system.init();
}

pub inline fn hang() noreturn {
    instructions.cli();

    while (true) {
        instructions.hlt();
    }
}
