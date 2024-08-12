const yos = @import("yos");

export fn _start() noreturn {
    yos.console.print("Welcome Back to Y Operating System!\n", .{});

    const yui_pid = yos.fork();

    if (yui_pid == 0) {
        const result = yos.execv(&.{"/usr/bin/yui"});

        if (result != 0) {
            yos.console.print("Could not initialize YUI: {}\n", .{result});
        }
    }

    while (true) {}
}
