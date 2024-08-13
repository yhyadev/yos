//! Screen
//!
//! An abstraction over framebuffers so it is easier to manage

const abi = @import("abi");
const limine = @import("limine");

const arch = @import("arch.zig");

export var framebuffer_request: limine.FramebufferRequest = .{};

pub var framebuffers: []*limine.Framebuffer = undefined;
pub var framebuffer: *limine.Framebuffer = undefined;

pub fn get(x: u64, y: u64) *abi.Color {
    const pixel_size = @sizeOf(abi.Color);
    const pixel_offset = x * pixel_size + y * framebuffer.pitch;

    return @as(*abi.Color, @ptrCast(@alignCast(framebuffer.address + pixel_offset)));
}

pub fn init() void {
    const maybe_framebuffer_response = framebuffer_request.response;

    if (maybe_framebuffer_response == null or maybe_framebuffer_response.?.framebuffers().len == 0) {
        arch.cpu.process.hang();
    }

    const framebuffer_response = maybe_framebuffer_response.?;

    framebuffers = framebuffer_response.framebuffers();
    framebuffer = framebuffers[0];
}
