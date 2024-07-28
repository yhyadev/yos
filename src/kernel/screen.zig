const limine = @import("limine");

const arch = @import("arch.zig");

export var framebuffer_request: limine.FramebufferRequest = .{};

pub var framebuffers: []*limine.Framebuffer = undefined;
pub var framebuffer: *limine.Framebuffer = undefined;

pub fn init() void {
    const framebuffer_response = framebuffer_request.response;

    if (framebuffer_response == null or framebuffer_response.?.framebuffers().len == 0) {
        arch.hang();
    }

    framebuffers = framebuffer_response.?.framebuffers();
    framebuffer = framebuffers[0];
}

pub const Color = packed struct(u32) {
    b: u8,
    g: u8,
    r: u8,
    a: u8,

    pub const white: Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const red: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    pub const blue: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };
    pub const green: Color = .{ .r = 0, .g = 255, .b = 0, .a = 255 };
};

pub fn putPixel(x: u64, y: u64, color: Color) void {
    const pixel_offset = x * 4 + y * framebuffer.pitch;

    @as(*Color, @ptrCast(@alignCast(framebuffer.address + pixel_offset))).* = color;
}
