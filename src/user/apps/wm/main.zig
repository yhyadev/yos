const core = @import("core");

const loop = @import("loop.zig");

pub const panic = core.console.panic;

export fn _start() noreturn {
    const allocator = core.memory.allocator();

    loop.start(allocator);
}
