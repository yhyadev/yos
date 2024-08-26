//! Loop
//!
//! The event loop that runs all the time, contains key mapping to actions and other functionalities

const std = @import("std");
const abi = @import("abi");

const display = @import("display.zig");

pub fn start() noreturn {
    while (true) {
        display.clearBackground(abi.Color.black);

        display.synchronize();
    }
}
