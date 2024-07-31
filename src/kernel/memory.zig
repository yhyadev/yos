const std = @import("std");
const limine = @import("limine");

const arch = @import("arch.zig");

const SpinLock = @import("locks/SpinLock.zig");

export var memory_map_request: limine.MemoryMapRequest = .{};
export var hhdm_request: limine.HhdmRequest = .{};

var memory_region: []u8 = undefined;
var hhdm_offset: u64 = undefined;

pub const PageAllocator = struct {
    var initialized = false;

    const min_page_size = 4096;

    var page_bitmap: []u8 = undefined;
    var page_count: u64 = 0;

    var mutex: SpinLock = .{};

    pub const vtable: std.mem.Allocator.VTable = .{
        .alloc = alloc,
        .resize = std.mem.Allocator.noResize,
        .free = free,
    };

    pub fn init() void {
        page_count = std.math.divCeil(usize, memory_region.len, min_page_size) catch unreachable;

        const required_page_count = std.math.divCeil(usize, page_count, min_page_size) catch unreachable;

        if (memory_region.len < min_page_size or memory_region.len < required_page_count * min_page_size) {
            @panic("minimum required usable memory exceeded the actual usable memory");
        }

        page_bitmap = memory_region[0..page_count];

        @memset(page_bitmap, 0);

        for (0..required_page_count) |i| {
            page_bitmap[i] = 1;
        }

        initialized = true;
    }

    fn alloc(_: *anyopaque, len: usize, _: u8, _: usize) ?[*]u8 {
        std.debug.assert(len > 0);

        mutex.lock();
        defer mutex.unlock();

        if (!initialized) PageAllocator.init();

        const required_page_count = std.math.divCeil(usize, len, min_page_size) catch unreachable;

        if (required_page_count > page_count) return null;

        var first_available_page: usize = 0;
        var available_page_count: usize = 0;

        for (page_bitmap, 0..) |page_bit, i| {
            if (page_bit == 0) {
                if (available_page_count == 0) first_available_page = i;

                if (required_page_count == 1 or available_page_count == required_page_count - 1) {
                    for (first_available_page..i + 1) |j| {
                        page_bitmap[j] = 1;
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

        for (0..page_bitmap.len) |i| {
            if ((memory_region.ptr + (i * min_page_size)) == buf.ptr) {
                for (i..i + required_page_count) |j| {
                    page_bitmap[j] = 0;
                }

                break;
            }
        }
    }
};

pub inline fn virtFromPhys(phys: u64) u64 {
    return phys + hhdm_offset;
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
            best_memory_region = @as([*]u8, @ptrFromInt(virtFromPhys(memory_map_entry.base)))[0..memory_map_entry.length];
        }
    }

    if (best_memory_region == null) {
        @panic("could not find a usable memory region");
    }

    memory_region = best_memory_region.?;
}
