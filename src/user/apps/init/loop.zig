//! Loop
//!
//! The event loop that runs all the time, contains key mapping to actions and other functionalities

const abi = @import("abi");
const yos = @import("yos");

const display = @import("display.zig");

pub fn start() noreturn {
    while (true) {
        display.drawRectangle(0, 0, display.state.width, display.state.height, abi.Color.black);

        display.synchronize();
    }
}
