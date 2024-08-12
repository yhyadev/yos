const yos = @import("yos");

export fn _start() noreturn {
    const yui_pid = yos.fork();

    if (yui_pid == 0) {
        const result = yos.execv(&.{"/usr/bin/yui"});

        if (result != 0) {
            yos.console.print("could not initialize yui: {}\n", .{result});
        }
    } else {
        yos.wait(yui_pid);
    }

    while (true) {}
}
