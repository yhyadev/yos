//! Loop
//!
//! The event loop that runs all the time, contains key mapping to actions and other functionalities

const std = @import("std");
const abi = @import("abi");
const core = @import("core");

const display = @import("display.zig");

pub fn start(allocator: std.mem.Allocator) noreturn {
    core.framebuffer.init();

    display.init(allocator) catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
    };

    while (true) {
        display.clearBackground(abi.Color.black);

        display.synchronize();
    }
}
