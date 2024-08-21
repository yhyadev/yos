const core = @import("core");

pub const panic = core.console.panic;

export fn _start() noreturn {
    core.console.print("{s}\n", .{core.process.env.get("PWD").?});

    core.process.exit(0);
}
