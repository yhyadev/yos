const core = @import("core");

const display = @import("display.zig");
const loop = @import("loop.zig");

pub const panic = core.console.panic;

export fn _start() noreturn {
    const allocator = core.memory.allocator();

    // Initialize the display we need to use instead of putting colors on the screen manually
    display.init(allocator) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
    };

    // Start the event loop after initializing all required features
    loop.start();
}
