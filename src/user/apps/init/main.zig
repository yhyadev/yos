const yos = @import("yos");

fn gui() void {
    const pid = yos.fork();

    if (pid == 0) {
        const result = yos.execv(&.{"/usr/bin/gui"});

        if (result != 0) {
            yos.console.print("could not initialize gui: {}\n", .{result});
        }
    }
}

export fn _start() noreturn {
    gui();

    while (true) {}
}
