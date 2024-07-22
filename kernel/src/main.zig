const std = @import("std");
const limine = @import("limine");

// Set the base revision to 2, this is recommended as this is the latest
// base revision described by the Limine boot protocol specification
pub export var base_revision: limine.BaseRevision = .{ .revision = 2 };

// Set the stack size to a reasonable size
pub export var stack_size_request: limine.StackSizeRequest = .{ .stack_size = 16 * 1024 };

pub inline fn hang() noreturn {
    // Clear the interrupt flag (IF)
    asm volatile ("cli");

    while (true) {
        // Wait for another interrupt until the next iteration, this usually used to put the CPU to sleep
        asm volatile ("hlt");
    }
}

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, return_address: ?usize) noreturn {
    _ = stack_trace;
    _ = return_address;

    // TODO: Print this message somewhere
    _ = message;

    hang();
}

export fn _start() callconv(.C) noreturn {
    if (!base_revision.is_supported()) {
        @panic("Limine bootloader base revision is not supported");
    }

    hang();
}
