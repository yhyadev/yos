const core = @import("core");

const display = @import("display.zig");
const loop = @import("loop.zig");

pub const panic = core.console.panic;

export fn _start() noreturn {
    const allocator = core.memory.allocator();

    core.framebuffer.init();

    display.init(allocator) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
    };

    loop.start();
}
