const core = @import("core");

pub const panic = core.console.panic;

fn startWindowManager() noreturn {
    const result = core.process.execve(&.{"wm"}, &.{});

    switch (result) {
        -1 => @panic("the window manager is not found"),
        -2 => @panic("a component in the window manger path is not a directory"),
        -3 => @panic("the window manager path is not absolute (can be resulted by a bad PATH or PWD environment variables)"),
        -4 => @panic("the window manager elf file is incorrect"),
        -5 => @panic("we passed a bad environment pair into execve syscall"),
        else => @panic("could not run the window manager for unknown reason"),
    }
}

export fn _start() noreturn {
    startWindowManager();
}
