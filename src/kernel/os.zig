const std = @import("std");

const memory = @import("memory.zig");

pub const heap = struct {
    pub const page_allocator: std.mem.Allocator = .{
        .ptr = undefined,
        .vtable = &memory.PageAllocator.vtable,
    };
};

pub const NAME_MAX = 255;
