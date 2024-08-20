//! Y Window Manager

const std = @import("std");
const core = @import("core");

const display = @import("wm/display.zig");
const loop = @import("wm/loop.zig");

pub fn start(allocator: std.mem.Allocator) noreturn {
    // Initialize the framebuffer (which is just getting it via a system call)
    core.framebuffer.init();

    // Initialize the display we need to use instead of putting colors on the screen manually
    display.init(allocator) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
    };

    // Start the event loop after initializing all required features
    loop.start();
}
