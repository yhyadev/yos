//! Paging
//!
//! An implementation of 4 levels paging functionality

const std = @import("std");
const limine = @import("limine");

const cpu = @import("cpu.zig");
const memory = @import("../../memory.zig");

pub var base_page_table: *PageTable = undefined;

pub const PageTable = extern struct {
    entries: [4 * 128]Entry,

    const Entry = packed struct(u64) {
        present: bool,
        writable: bool,
        user: bool,
        write_through: bool,
        no_cache: bool,
        accessed: bool = false,
        dirty: bool = false,
        huge: bool,
        global: bool,
        reserved_1: u3 = 0,
        aligned_physical_address: u40,
        reserved_2: u11 = 0,
        no_exe: bool,

        /// Get the page table pointed by this entry. Should not be called on L1
        /// entries, which point to physical frames of  instead of a page
        /// table. Returns a virtual address space pointer using HHDM.
        pub inline fn getTable(self: Entry) *PageTable {
            return @ptrFromInt(virtualFromPhysical(self.aligned_physical_address << 12));
        }
    };
};

pub const Indices = struct {
    offset: u12,
    level_1: u9,
    level_2: u9,
    level_3: u9,
    level_4: u9,
};

pub inline fn indicesFromAddress(address: usize) Indices {
    return .{
        .offset = @truncate(address),
        .level_1 = @truncate(address >> 12),
        .level_2 = @truncate(address >> 21),
        .level_3 = @truncate(address >> 30),
        .level_4 = @truncate(address >> 39),
    };
}

pub inline fn addressFromIndices(address: Indices) usize {
    var result: usize = 0;

    result += address.offset;
    result += @as(usize, address.level_1) << 12;
    result += @as(usize, address.level_2) << 21;
    result += @as(usize, address.level_3) << 30;
    result += @as(usize, address.level_4) << 39;

    if ((result & (@as(usize, 1) << 47)) != 0) {
        for (48..64) |i| {
            result |= (@as(usize, 1) << @truncate(i));
        }
    }

    return result;
}

pub inline fn virtualFromPhysical(physical: u64) u64 {
    return physical + memory.hhdm_offset;
}

pub fn physicalFromVirtual(level_4: *PageTable, virtual: usize) ?usize {
    const indices = indicesFromAddress(virtual);

    var page_table = level_4;

    var level: usize = 4;

    inline for (&.{ indices.level_4, indices.level_3, indices.level_2 }) |page_index| {
        const page = page_table.entries[page_index];

        if (!page.present) return null;

        if (page.huge) {
            switch (level) {
                inline 1, 4 => |i| @panic(std.fmt.comptimePrint("PS flag set on a level {} page", .{i})),

                2 => {
                    return (page.aligned_physical_address << 21) + (@as(usize, indices.level_1) << 12) + indices.offset;
                },

                3 => @panic("1 GiB level 3 pages is not supported"),

                else => unreachable,
            }
        }

        page_table = page.getTable();

        level -= 1;
    }

    if (!page_table.entries[indices.level_1].present) return null;

    return (page_table.entries[indices.level_1].aligned_physical_address << 12) + indices.offset;
}

pub inline fn getActivePageTable() *PageTable {
    return @ptrFromInt(virtualFromPhysical(cpu.registers.Cr3.read()));
}

pub inline fn setActivePageTable(page_table: *PageTable) void {
    cpu.registers.Cr3.write(physicalFromVirtual(getActivePageTable(), @intFromPtr(page_table)).?);
}

pub const MapPageOptions = struct {
    writable: bool,
    executable: bool,
    user: bool,
    global: bool,
};

pub fn mapPage(allocator: std.mem.Allocator, level_4: *PageTable, virtual_address: usize, physical_address: usize, options: MapPageOptions) !void {
    std.debug.assert(virtual_address % std.mem.page_size == 0);
    std.debug.assert(physical_address % std.mem.page_size == 0);

    const indices = indicesFromAddress(virtual_address);

    std.debug.assert(indices.offset == 0);

    var page_table = level_4;

    inline for (&.{ indices.level_4, indices.level_3, indices.level_2 }) |page_index| {
        const page = page_table.entries[page_index];

        if (page.present) {
            if (page.huge) @panic("huge pages is not implemented");

            page_table = page.getTable();
        } else {
            const new_page_table = try allocPageTable(allocator);

            std.debug.assert(isValid(new_page_table, 1));

            page_table.entries[page_index] = .{
                .present = true,
                .writable = true,
                .user = true,
                .write_through = true,
                .no_cache = true,
                .huge = false,
                .global = false,
                .no_exe = false,
                .aligned_physical_address = @truncate(physicalFromVirtual(getActivePageTable(), @intFromPtr(&new_page_table.entries)).? >> 12),
            };

            page_table = page_table.entries[page_index].getTable();
        }
    }

    const was_present = page_table.entries[indices.level_1].present;

    page_table.entries[indices.level_1] = .{
        .present = true,
        .writable = options.writable,
        .user = options.user,
        .write_through = true,
        .no_cache = true,
        .huge = false,
        .global = options.global,
        .no_exe = !options.executable,
        .aligned_physical_address = @truncate(physical_address >> 12),
    };

    if (was_present) {
        cpu.paging.invlpg(virtual_address);
    }
}

pub const PageTableModifications = struct {
    writable: ?bool = null,
    executable: ?bool = null,
    user: ?bool = null,
    global: ?bool = null,
    write_through: ?bool = null,
    no_cache: ?bool = null,
};

pub fn modifyRecursive(page_table: *PageTable, level: usize, modifications: PageTableModifications) void {
    for (0..page_table.len) |i| {
        const page = &page_table.entries[i];

        if (page.present) {
            if (modifications.writable) |writable| {
                page.writable = writable;
            }

            if (modifications.executable) |executable| {
                page.no_exe = !executable;
            }

            if (modifications.user) |user| {
                page.user = user;
            }

            if (modifications.global) |global| {
                page.global = global;
            }

            if (modifications.write_through) |write_through| {
                page.write_through = write_through;
            }

            if (modifications.no_cache) |no_cache| {
                page.no_cache = no_cache;
            }

            if (level > 1) {
                modifyRecursive(page.getTable(), level - 1, modifications);
            }
        }
    }
}

pub const UnmapPageError = error{NotMapped};

pub fn unmapPage(level_4: *PageTable, virtual_address: usize) void {
    std.debug.assert(virtual_address % std.mem.page_size == 0);

    const indices = indicesFromAddress(virtual_address);

    std.debug.assert(indices.offset == 0);

    var page_table = level_4;

    inline for (&.{ indices.level_4, indices.level_3, indices.level_2 }) |page_index| {
        const page = page_table.entries[page_index];

        if (!page.present) return;

        if (page.huge) @panic("Huge pages not implemented");

        page_table = page.getTable();
    }

    page_table.entries[indices.level_1].present = false;
}

pub fn mapKernel(page_table: *PageTable) void {
    for (256..512) |i| {
        const base_entry = base_page_table.entries[i];

        if (base_entry.present) {
            page_table.entries[i] = base_entry;
        }
    }
}

pub fn isValid(page_table: *PageTable, level: usize) bool {
    for (page_table.entries) |page| {
        if (page.reserved_1 != 0 or page.reserved_2 != 0) return false;
        if (page.huge) return true; // TODO: Check huge pages
        if (level > 1 and page.present and !isValid(page.getTable(), level - 1)) return false;
    }

    return true;
}

pub fn allocPageTable(allocator: std.mem.Allocator) !*PageTable {
    const new_page_table = &((try allocator.allocWithOptions(PageTable, 1, std.mem.page_size, null))[0]);
    new_page_table.* = std.mem.zeroes(PageTable);

    mapKernel(new_page_table);

    return new_page_table;
}

pub fn dupePageTableLevel(allocator: std.mem.Allocator, page_table: *PageTable, level: usize) !*PageTable {
    const new_page_table = try allocPageTable(allocator);

    for (page_table.entries, 0..) |page, i| {
        if (level == 4 and i >= 256) break;

        new_page_table.entries[i] = page;

        if (level > 1 and page.present) {
            const child = try dupePageTableLevel(allocator, page.getTable(), level - 1);

            new_page_table.entries[i].aligned_physical_address = @truncate(physicalFromVirtual(getActivePageTable(), @intFromPtr(child)).? >> 12);
        }
    }

    return new_page_table;
}

pub fn dupePageTable(allocator: std.mem.Allocator, page_table: *PageTable) !*PageTable {
    return dupePageTableLevel(allocator, page_table, 4);
}

pub fn init() void {
    base_page_table = getActivePageTable();
}
