const core = @import("core");

const wm = @import("wm.zig");

pub const panic = core.console.panic;

export fn _start() noreturn {
    const allocator = core.memory.allocator();

    wm.start(allocator);
}
