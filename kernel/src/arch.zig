const builtin = @import("builtin");

pub const instructions = switch (builtin.target.cpu.arch) {
    .x86_64 => @import("arch/x86_64/instructions.zig"),
    else => @compileError("Target CPU is not supported"),
};

pub inline fn hang() noreturn {
    instructions.cli();

    while (true) {
        instructions.hlt();
    }
}
