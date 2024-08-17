//! Y Window Manager

const std = @import("std");

const display = @import("wm/display.zig");
const loop = @import("wm/loop.zig");

pub fn start(allocator: std.mem.Allocator) noreturn {
    // Initialize the display we need to use instead of putting colors on the screen manually
    display.init(allocator) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
    };

    // Start the event loop after initializing all required features
    loop.start();
}
