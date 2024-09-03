//! Memory Allocation
//!
//! An implementaion of various memory allocators such as page allocator

const std = @import("std");
const limine = @import("limine");

const higher_half = @import("higher_half.zig");

const SpinLock = @import("locks/SpinLock.zig");

export var memory_map_request: limine.MemoryMapRequest = .{};

pub var memory_region: []u8 = undefined;

pub const user_allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &struct {
        pub const vtable: std.mem.Allocator.VTable = .{
            .alloc = &alloc,
            .resize = &std.mem.Allocator.noResize,
            .free = &free,
        };

        const mmap = @import("syscall.zig").mmap;
        const munmap = @import("syscall.zig").munmap;

        fn alloc(_: *anyopaque, bytes_len: usize, _: u8, _: usize) ?[*]u8 {
            var context: @import("arch.zig").cpu.process.Context = .{};
            mmap(&context, 0, bytes_len, 2, 0);
            return @ptrFromInt(context.rax);
        }

        fn free(_: *anyopaque, bytes: []u8, _: u8, _: usize) void {
            munmap(undefined, @intFromPtr(bytes.ptr), bytes.len);
        }
    }.vtable,
};

pub const PageAllocator = struct {
    var initialized = false;

    var mutex: SpinLock = .{};

    var page_bitmap: std.DynamicBitSetUnmanaged = .{};

    var total_page_count: usize = 0;

    pub const vtable: std.mem.Allocator.VTable = .{
        .alloc = &alloc,
        .resize = &resize,
        .free = &free,
    };

    pub fn init() std.mem.Allocator.Error!void {
        total_page_count = std.math.divCeil(usize, memory_region.len, std.mem.page_size) catch unreachable;

        const required_page_count = std.math.divCeil(usize, total_page_count, std.mem.page_size * @sizeOf(std.DynamicBitSetUnmanaged.MaskInt)) catch unreachable;

        var page_bitmap_allocator: std.heap.FixedBufferAllocator = .init(memory_region);

        page_bitmap = try .initEmpty(page_bitmap_allocator.allocator(), total_page_count);

        for (0..required_page_count) |i| {
            page_bitmap.set(i);
        }

        initialized = true;
    }

    fn alloc(_: *anyopaque, bytes_len: usize, _: u8, _: usize) ?[*]u8 {
        std.debug.assert(bytes_len > 0);

        mutex.lock();
        defer mutex.unlock();

        if (!initialized) PageAllocator.init() catch return null;

        const required_page_count = std.math.divCeil(usize, bytes_len, std.mem.page_size) catch unreachable;

        if (required_page_count > total_page_count) return null;

        var i: usize = 0;

        while (i < total_page_count) : (i += 1) {
            if (!page_bitmap.isSet(i)) retry: {
                if (i + required_page_count > total_page_count) return null;

                for (i..i + required_page_count) |j| {
                    if (page_bitmap.isSet(j)) {
                        i += j - i;

                        break :retry;
                    }
                }

                for (i..i + required_page_count) |j| {
                    page_bitmap.set(j);
                }

                return memory_region[i * std.mem.page_size .. (i + 1) * std.mem.page_size].ptr;
            }
        }

        return null;
    }

    fn resize(_: *anyopaque, bytes: []u8, _: u8, new_bytes_len: usize, _: usize) bool {
        const used_page_count = std.math.divCeil(usize, bytes.len, std.mem.page_size) catch unreachable;
        const new_page_count = std.math.divCeil(usize, new_bytes_len, std.mem.page_size) catch unreachable;

        if (new_page_count == used_page_count) {
            return true;
        }

        if (new_page_count < used_page_count) {
            free(undefined, (bytes.ptr + new_page_count * std.mem.page_size)[0 .. (used_page_count - new_page_count) * std.mem.page_size], 0, 0);

            return true;
        }

        if (new_page_count > used_page_count) {
            for (0..total_page_count) |i| {
                if ((memory_region.ptr + (i * std.mem.page_size)) == (bytes.ptr + (used_page_count * std.mem.page_size))) {
                    for (i..i + new_page_count) |j| {
                        if (page_bitmap.isSet(j)) {
                            return false;
                        }
                    }

                    for (i..i + new_page_count) |j| {
                        page_bitmap.set(j);
                    }

                    return true;
                }
            }
        }

        return false;
    }

    fn free(_: *anyopaque, bytes: []u8, _: u8, _: usize) void {
        std.debug.assert(bytes.len > 0);

        mutex.lock();
        defer mutex.unlock();

        if (!initialized) @panic("free is called while the page allocator is not initialized");

        const used_page_count = std.math.divCeil(usize, bytes.len, std.mem.page_size) catch unreachable;

        for (0..total_page_count) |i| {
            if ((memory_region.ptr + (i * std.mem.page_size)) == bytes.ptr) {
                for (i..i + used_page_count) |j| {
                    page_bitmap.toggle(j);
                }

                break;
            }
        }
    }
};

pub fn init() void {
    const maybe_memory_map_response = memory_map_request.response;

    if (maybe_memory_map_response == null) {
        @panic("could not retrieve information about the ram");
    }

    const memory_map_respone = maybe_memory_map_response.?;

    var best_memory_region: ?[]u8 = null;

    for (memory_map_respone.entries()) |memory_map_entry| {
        if (memory_map_entry.kind == .usable and (best_memory_region == null or memory_map_entry.length > best_memory_region.?.len)) {
            best_memory_region = @as([*]u8, @ptrFromInt(higher_half.virtualFromPhysical(memory_map_entry.base)))[0..memory_map_entry.length];
        }
    }

    if (best_memory_region == null) {
        @panic("could not find a usable memory region");
    }

    memory_region = best_memory_region.?;
}
