const yos = @import("yos");

export fn _start() noreturn {
    yos.console.print("=> Initializing YUI..\n", .{});

    const screen_width = yos.screen.width();
    const screen_height = yos.screen.width();

    for (0..screen_height) |y| {
        for (0..screen_width) |x| {
            yos.screen.put(x, y, yos.screen.Color.black);
        }
    }

    while (true) {}
}
