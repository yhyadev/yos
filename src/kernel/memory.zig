//! Memory Allocation
//!
//! An implementaion of various memory allocators such as page allocator

const std = @import("std");
const limine = @import("limine");

const arch = @import("arch.zig");

const SpinLock = @import("locks/SpinLock.zig");

export var memory_map_request: limine.MemoryMapRequest = .{};
export var hhdm_request: limine.HhdmRequest = .{};

/// The best memory region we could find
var memory_region: []u8 = undefined;

/// Higher Half Direct Memory Offset, which is just a way to say an offset
/// of physical memory to virtual memory
var hhdm_offset: u64 = undefined;

pub const PageAllocator = struct {
    var initialized = false;

    var mutex: SpinLock = .{};

    const min_page_size = std.mem.page_size;

    var page_bitmap: std.DynamicBitSetUnmanaged = .{};

    var page_count: u64 = 0;

    pub const vtable: std.mem.Allocator.VTable = .{
        .alloc = alloc,
        .resize = std.mem.Allocator.noResize,
        .free = free,
    };

    pub fn init() std.mem.Allocator.Error!void {
        page_count = std.math.divCeil(usize, memory_region.len, min_page_size) catch unreachable;

        const required_page_count = std.math.divCeil(usize, page_count, min_page_size * @sizeOf(std.DynamicBitSetUnmanaged.MaskInt)) catch unreachable;

        var page_bitmap_allocator = std.heap.FixedBufferAllocator.init(memory_region);

        page_bitmap = try std.DynamicBitSetUnmanaged.initEmpty(page_bitmap_allocator.allocator(), page_count);

        for (0..required_page_count) |i| {
            page_bitmap.set(i);
        }

        initialized = true;
    }

    fn alloc(_: *anyopaque, len: usize, _: u8, _: usize) ?[*]u8 {
        std.debug.assert(len > 0);

        mutex.lock();
        defer mutex.unlock();

        if (!initialized) PageAllocator.init() catch return null;

        const required_page_count = std.math.divCeil(usize, len, min_page_size) catch unreachable;

        if (required_page_count > page_count) return null;

        var first_available_page: usize = 0;
        var available_page_count: usize = 0;

        for (0..page_count - 1) |i| {
            if (!page_bitmap.isSet(i)) {
                if (available_page_count == 0) first_available_page = i;

                if (required_page_count == 1 or available_page_count == required_page_count - 1) {
                    for (first_available_page..i + 1) |j| {
                        page_bitmap.set(j);
                    }

                    return memory_region[first_available_page * min_page_size .. (i + 1) * min_page_size].ptr;
                }

                available_page_count += 1;
            } else {
                first_available_page = 0;
                available_page_count = 0;
            }
        }

        return null;
    }

    fn free(_: *anyopaque, buf: []u8, _: u8, _: usize) void {
        std.debug.assert(buf.len > 0);

        mutex.lock();
        defer mutex.unlock();

        if (!initialized) @panic("free is called while the page allocator is not initialized");

        const required_page_count = std.math.divCeil(usize, buf.len, min_page_size) catch unreachable;

        for (0..page_count) |i| {
            if ((memory_region.ptr + (i * min_page_size)) == buf.ptr) {
                for (i..i + required_page_count) |j| {
                    page_bitmap.toggle(j);
                }

                break;
            }
        }
    }
};

pub inline fn virtualFromPhysical(physical: u64) u64 {
    return physical + hhdm_offset;
}

pub fn init() void {
    const maybe_hhdm_response = hhdm_request.response;
    const maybe_memory_map_response = memory_map_request.response;

    if (maybe_hhdm_response == null or maybe_memory_map_response == null) {
        @panic("could not retrieve information about the ram");
    }

    const hhdm_response = maybe_hhdm_response.?;
    const memory_map_respone = maybe_memory_map_response.?;

    hhdm_offset = hhdm_response.offset;

    var best_memory_region: ?[]u8 = null;

    for (memory_map_respone.entries()) |memory_map_entry| {
        if (memory_map_entry.kind == .usable and (best_memory_region == null or memory_map_entry.length > best_memory_region.?.len)) {
            best_memory_region = @as([*]u8, @ptrFromInt(virtualFromPhysical(memory_map_entry.base)))[0..memory_map_entry.length];
        }
    }

    if (best_memory_region == null) {
        @panic("could not find a usable memory region");
    }

    memory_region = best_memory_region.?;
}
