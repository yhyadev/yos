//! Crash
//!
//! When there is an error, here is the where we display it

const std = @import("std");

const arch = @import("arch.zig");
const console = @import("console.zig");

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    arch.cpu.interrupts.disable();

    // The console should not in any way be the error, this must work
    console.print("\npanic: {s}\n", .{message});

    arch.cpu.process.hang();
}
