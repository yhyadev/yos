const std = @import("std");
const core = @import("core");

pub const panic = core.console.panic;

export fn _start() noreturn {
    core.gui.initWindow(800, 600);

    core.process.exit(0);
}
