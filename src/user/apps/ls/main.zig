const std = @import("std");
const core = @import("core");

pub const panic = core.console.panic;

fn list_dir(path: []const u8) void {
    const dir_open_result = core.fs.open(path);

    switch (dir_open_result) {
        -1, -2, -3 => std.debug.panic("{s}: no such file or directory", .{path}),

        else => {},
    }

    const dir_fd: usize = @intCast(dir_open_result);

    var dir_entries: [1]@import("abi").DirEntry = undefined;

    var dir_entries_len: usize = 0;

    for (0..std.math.maxInt(usize)) |dir_entry_offset| {
        dir_entries_len = core.fs.readdir(dir_fd, dir_entry_offset, &dir_entries);

        if (dir_entries_len == 0) {
            core.console.print("\n", .{});

            break;
        }

        core.console.print("{s} ", .{dir_entries[0].name});
    }
}

export fn _start() noreturn {
    const argv = core.process.getargv();

    if (argv.len == 1) {
        list_dir(core.process.env.get("PWD").?);
    } else {
        for (argv[1..]) |arg| {
            if (argv.len > 2) {
                core.console.print("{s}:\n", .{arg});
            }

            list_dir(std.mem.span(arg));

            if (argv.len > 2) {
                core.console.print("\n", .{});
            }
        }
    }

    core.process.exit(0);
}
