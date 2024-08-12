const yos = @import("yos");

export fn _start() noreturn {
    const yui_pid = yos.fork();

    if (yui_pid == 0) {
        const result = yos.execv(&.{"/usr/bin/gui"});

        if (result != 0) {
            yos.console.print("could not initialize gui: {}\n", .{result});
        }
    }

    while (true) {}
}
