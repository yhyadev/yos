const std = @import("std");
const core = @import("core");

pub const panic = core.console.panic;

export fn _start() noreturn {
    const argv = core.process.getargv();

    if (argv.len == 1) {
        @panic("missing operand");
    }

    for (argv[1..]) |arg| {
        const path = std.mem.span(arg);

        switch (core.fs.mkdir(path)) {
            -1, -2, -3 => std.debug.panic("{s}: no such file or directory", .{path}),
            -4 => std.debug.panic("{s}: already exists", .{path}),

            else => {},
        }
    }

    core.process.exit(0);
}
