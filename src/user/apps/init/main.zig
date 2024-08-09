const yos = @import("yos");

export fn _start() noreturn {
    main();

    yos.exit(0);
}

fn main() void {
    yos.console.print("Welcome Back to Y Operating System!\n", .{});
}
