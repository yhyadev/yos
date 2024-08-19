const core = @import("core");

export fn _start() noreturn {
    core.console.print("{s}", .{core.env.get("PWD").?});

    core.process.exit(0);
}
