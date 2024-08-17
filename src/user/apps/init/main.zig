const yos = @import("yos");

const display = @import("display.zig");
const loop = @import("loop.zig");

pub const panic = yos.console.panic;

export fn _start() noreturn {
    const allocator = yos.memory.allocator();

    // Initialize the display we need to use instead of putting colors on the screen manually
    display.init(allocator) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
    };

    // Start the event loop after initializing all required features
    loop.start();
}
