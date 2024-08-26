const std = @import("std");
const core = @import("core");

pub const panic = core.console.panic;

export fn _start() noreturn {
    const argv = core.process.getargv();

    if (argv.len == 1) {
        @panic("missing operand");
    }

    for (argv[1..]) |arg_ptr| {
        const arg = std.mem.span(arg_ptr);

        if (std.mem.eql(u8, arg, "--help")) {
            core.console.print(
                \\Usage: {s} <FILE..>
                \\
                \\Make FILE(s), if they do not already exist.
            , .{argv[0]});

            break;
        }
    }

    for (argv[1..]) |arg_ptr| {
        const arg = std.mem.span(arg_ptr);

        switch (core.fs.mkfile(arg)) {
            -1, -2, -3 => std.debug.panic("{s}: no such file or directory", .{arg}),

            else => {},
        }
    }

    core.process.exit(0);
}
