//! Loop
//!
//! The event loop that runs all the time, contains key mapping to actions and other functionalities

const abi = @import("abi");
const core = @import("core");

const display = @import("display.zig");

pub fn start() noreturn {
    const pid = core.process.fork();

    if (pid == 0) {
        while (true) {
            display.synchronize();
        }
    } else {
        const colors: []const abi.Color = &.{ abi.Color.red, abi.Color.blue, abi.Color.green };

        var i: usize = 0;

        while (true) {
            display.clearBackground(colors[i]);

            if (i < 2) i += 1 else i = 0;
        }
    }
}
