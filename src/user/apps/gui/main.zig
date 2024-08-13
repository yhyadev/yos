const abi = @import("abi");
const yos = @import("yos");

export fn _start() noreturn {
    const screen_width = yos.screen.width();
    const screen_height = yos.screen.width();

    for (0..screen_height) |y| {
        for (0..screen_width) |x| {
            yos.screen.put(x, y, abi.Color.black);
        }
    }

    while (true) {}
}
