//! Crash
//!
//! When there is an error, here is the where we display it

const std = @import("std");

const arch = @import("arch.zig");
const tty = @import("tty.zig");

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    arch.cpu.interrupts.disable();

    // The tty should not in any way be the error, this must work
    tty.print("\npanic: {s}\n", .{message});

    arch.cpu.hang();
}
