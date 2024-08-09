//! Screen
//!
//! An abstraction over framebuffers so it is easier to manage

const limine = @import("limine");

const arch = @import("arch.zig");

export var framebuffer_request: limine.FramebufferRequest = .{};

pub var framebuffers: []*limine.Framebuffer = undefined;
pub var framebuffer: *limine.Framebuffer = undefined;

pub const Color = packed struct(u32) {
    b: u8,
    g: u8,
    r: u8,
    padding: u8 = 0,

    pub const white: Color = .{ .r = 255, .g = 255, .b = 255 };
    pub const black: Color = .{ .r = 0, .g = 0, .b = 0 };
    pub const red: Color = .{ .r = 255, .g = 0, .b = 0 };
    pub const blue: Color = .{ .r = 0, .g = 0, .b = 255 };
    pub const green: Color = .{ .r = 0, .g = 255, .b = 0 };
};

pub fn get(x: u64, y: u64) *Color {
    const pixel_size = @sizeOf(Color);
    const pixel_offset = x * pixel_size + y * framebuffer.pitch;

    return @as(*Color, @ptrCast(@alignCast(framebuffer.address + pixel_offset)));
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
