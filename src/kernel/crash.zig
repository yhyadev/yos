const std = @import("std");

const arch = @import("arch.zig");
const tty = @import("tty.zig");

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    arch.cpu.interrupts.disable();

    tty.print("\npanic: {s}\n", .{message});

    arch.hang();
}
