const std = @import("std");
const limine = @import("limine");

const arch = @import("arch.zig");

pub export var base_revision: limine.BaseRevision = .{ .revision = 2 };

pub export var stack_size_request: limine.StackSizeRequest = .{ .stack_size = 16 * 1024 };

pub export var framebuffer_request: limine.FramebufferRequest = .{};
var framebuffers: []*limine.Framebuffer = undefined;

export fn _start() callconv(.C) noreturn {
    // Check if limine understands our base revision
    if (!base_revision.is_supported()) {
        arch.hang();
    }

    // Framebuffers is required to complete the initialization
    if (framebuffer_request.response) |framebuffer_response| {
        framebuffers = framebuffer_response.framebuffers();
    } else {
        arch.hang();
    }

    // The kernel should not return no matter what
    arch.hang();
}

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, return_address: ?usize) noreturn {
    _ = stack_trace;
    _ = return_address;
    _ = message;

    arch.hang();
}
