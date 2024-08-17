//! Display
//!
//! A wrapper around the functionality of the screen, implements double buffering
//! and other ways of optimizing the user interface

const std = @import("std");
const abi = @import("abi");
const core = @import("core");

pub var state: State = .{};

pub const State = struct {
    buffer: []abi.Color = undefined,
    width: usize = 0,
    height: usize = 0,

    /// Get the front buffer that is currently displayed to the user
    pub fn getFrontBuffer(self: State) []abi.Color {
        return self.buffer[0 .. self.width * self.height];
    }

    /// Get the back bufer that is edited before updating the screen
    pub fn getBackBuffer(self: State) []abi.Color {
        return self.buffer[self.width * self.height ..];
    }
};

/// Draw a rectangle with the dimensions being the screen width and height respectively
pub fn clearBackground(color: abi.Color) void {
    drawRectangle(0, 0, state.width, state.height, color);
}

/// Draw a rectangle with x and y being the top left corner
pub fn drawRectangle(x: usize, y: usize, width: usize, height: usize, color: abi.Color) void {
    const back_buffer = state.getBackBuffer();

    for (y..y + height) |dy| {
        for (x..x + width) |dx| {
            if (dx > state.width or dy > state.height) continue;

            back_buffer[dx + dy * state.width] = color;
        }
    }
}

/// Synchronize buffers and put on screen all things that changed
pub fn synchronize() void {
    for (state.getFrontBuffer(), state.getBackBuffer(), 0..) |*front_color, back_color, i| {
        if (!std.meta.eql(front_color.*, back_color)) {
            front_color.* = back_color;

            core.screen.put(i % state.width, @divFloor(i, state.width), back_color);
        }
    }
}

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
    state.width = core.screen.width();
    state.height = core.screen.height();

    state.buffer = try allocator.alloc(abi.Color, state.width * state.height * 2);

    for (state.buffer) |*color| {
        color.* = abi.Color.black;
    }
}
