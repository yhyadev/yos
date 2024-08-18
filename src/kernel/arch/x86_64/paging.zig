//! Paging
//!
//! An implementation of 4 levels paging functionality

const std = @import("std");
const limine = @import("limine");

const cpu = @import("cpu.zig");
const higher_half = @import("../../higher_half.zig");

pub var kernel_page_table: *PageTable = undefined;

pub const PageTable = extern struct {
    entries: [4 * 128]Entry = .{.{}} ** (4 * 128),

    const Entry = packed struct(u64) {
        present: bool = false,
        writable: bool = false,
        user: bool = false,
        write_through: bool = false,
        no_cache: bool = false,
        accessed: bool = false,
        dirty: bool = false,
        huge: bool = false,
        global: bool = false,
        reserved_1: u3 = 0,
        aligned_physical_address: u40 = 0,
        reserved_2: u11 = 0,
        no_exe: bool = false,

        /// Get the page table pointed by this entry, This must not be called on L1
        /// entries, which point to physical frames of address space instead of a page
        /// table
        pub inline fn getTable(self: Entry) *PageTable {
            return @ptrFromInt(higher_half.virtualFromPhysical(self.aligned_physical_address << 12));
        }
    };

    /// Allocate a new page table with all entries are default
    pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!*PageTable {
        const new_page_table = &((try allocator.allocWithOptions(PageTable, 1, std.mem.page_size, null))[0]);
        new_page_table.* = .{};

        return new_page_table;
    }

    /// Clone the page table, which expects that it is level 4
    pub fn clone(self: *PageTable, allocator: std.mem.Allocator) std.mem.Allocator.Error!*PageTable {
        return self.cloneLevel(allocator, 4);
    }

    /// Clone the page table, which expects that it is the same level you provided
    pub fn cloneLevel(self: *PageTable, allocator: std.mem.Allocator, level: usize) std.mem.Allocator.Error!*PageTable {
        const new_page_table = try PageTable.init(allocator);

        new_page_table.mapKernel();

        for (self.entries, 0..) |page, i| {
            if (level == 4 and i >= 256) break;

            new_page_table.entries[i] = page;

            if (level > 1 and page.present) {
                const child_page = try page.getTable().cloneLevel(allocator, level - 1);

                new_page_table.entries[i].aligned_physical_address = @truncate(getActivePageTable().physicalFromVirtual(@intFromPtr(child_page)).? >> 12);
            }
        }

        return new_page_table;
    }

    pub const MapOptions = struct {
        user: bool,
        global: bool,
        writable: bool,
        executable: bool,
    };

    /// Map a virtual address into a specific entry in the page table that points into the physical address you provide
    pub fn map(self: *PageTable, allocator: std.mem.Allocator, virtual_address: usize, physical_address: usize, options: MapOptions) !void {
        std.debug.assert(virtual_address % std.mem.page_size == 0);
        std.debug.assert(physical_address % std.mem.page_size == 0);

        const indices = Indices.fromAddress(virtual_address);

        std.debug.assert(indices.offset == 0);

        var page_table = self;

        inline for (&.{ indices.level_4, indices.level_3, indices.level_2 }) |page_index| {
            const page = page_table.entries[page_index];

            if (!page.present) {
                const new_page_table = try PageTable.init(allocator);

                const page_table_physical_address = getActivePageTable().physicalFromVirtual(@intFromPtr(new_page_table)).?;

                page_table.entries[page_index] = .{
                    .present = true,
                    .writable = true,
                    .user = true,
                    .write_through = true,
                    .no_cache = true,
                    .huge = false,
                    .global = false,
                    .no_exe = false,
                    .aligned_physical_address = @truncate(page_table_physical_address >> 12),
                };

                page_table = new_page_table;
            } else {
                if (page.huge) {
                    @panic("huge pages are not implemented");
                }

                page_table = page.getTable();
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

    /// Unmap a virtual address in the page table
    pub fn unmap(self: *PageTable, virtual_address: usize) void {
        std.debug.assert(virtual_address % std.mem.page_size == 0);

        const indices = Indices.fromAddress(virtual_address);

        std.debug.assert(indices.offset == 0);

        var page_table = self;

        inline for (&.{ indices.level_4, indices.level_3, indices.level_2 }) |page_index| {
            const page = page_table.entries[page_index];

            if (!page.present) {
                return;
            }

            if (page.huge) {
                @panic("huge pages are not implemented");
            }

            page_table = page.getTable();
        }

        page_table.entries[indices.level_1].present = false;
    }

    /// Map the kernel entries into the page table
    pub fn mapKernel(self: *PageTable) void {
        for (256..512) |i| {
            const kernel_page = kernel_page_table.entries[i];

            if (kernel_page.present) {
                self.entries[i] = kernel_page;
            }
        }
    }

    /// Check if a virtual address is mapped or not
    pub fn mapped(self: *PageTable, virtual_address: usize) bool {
        const indices = Indices.fromAddress(virtual_address);

        var page_table = self;

        var level: usize = 4;

        inline for (&.{ indices.level_4, indices.level_3, indices.level_2 }) |page_index| {
            const page = page_table.entries[page_index];

            if (!page.present) return false;

            page_table = page.getTable();

            level -= 1;
        }

        return page_table.entries[indices.level_1].present;
    }

    /// Convert virtual addresses to physical addresses by traversing the page table
    pub fn physicalFromVirtual(self: *PageTable, virtual_address: usize) ?usize {
        const indices = Indices.fromAddress(virtual_address);

        var page_table = self;

        var level: usize = 4;

        inline for (&.{ indices.level_4, indices.level_3, indices.level_2 }) |page_index| {
            const page = page_table.entries[page_index];

            if (!page.present) return null;

            if (page.huge) {
                switch (level) {
                    inline 1, 4 => |i| @panic(std.fmt.comptimePrint("PS flag set on a level {} page", .{i})),

                    2 => return (page.aligned_physical_address << 12) + (@as(usize, indices.level_1) << 12) + indices.offset,

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

    pub const Modifications = struct {
        writable: ?bool = null,
        executable: ?bool = null,
        user: ?bool = null,
        global: ?bool = null,
        write_through: ?bool = null,
        no_cache: ?bool = null,
    };

    /// Modify the page table recursively until the page table level becomes 1
    pub fn modifyRecursive(self: *PageTable, level: usize, modifications: Modifications) void {
        for (0..self.len) |i| {
            const page = &self.entries[i];

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
                    page.getTable().modifyRecursive(level - 1, modifications);
                }
            }
        }
    }
};

pub const Indices = struct {
    offset: u12,
    level_1: u9,
    level_2: u9,
    level_3: u9,
    level_4: u9,

    pub inline fn fromAddress(address: usize) Indices {
        return .{
            .offset = @truncate(address),
            .level_1 = @truncate(address >> 12),
            .level_2 = @truncate(address >> 21),
            .level_3 = @truncate(address >> 30),
            .level_4 = @truncate(address >> 39),
        };
    }

    pub inline fn toAddress(self: Indices) usize {
        var result: usize = 0;

        result += self.offset;
        result += @as(usize, self.level_1) << 12;
        result += @as(usize, self.level_2) << 21;
        result += @as(usize, self.level_3) << 30;
        result += @as(usize, self.level_4) << 39;

        if ((result & (@as(usize, 1) << 47)) != 0) {
            for (48..64) |i| {
                result |= (@as(usize, 1) << @truncate(i));
            }
        }

        return result;
    }
};

/// Get the active page table by reading the control register number 3
pub inline fn getActivePageTable() *PageTable {
    return @ptrFromInt(higher_half.virtualFromPhysical(cpu.registers.Cr3.read()));
}

/// Set the active page table by writing to the control register number 3
pub inline fn setActivePageTable(page_table: *PageTable) void {
    cpu.registers.Cr3.write(getActivePageTable().physicalFromVirtual(@intFromPtr(page_table)).?);
}

pub fn init() void {
    kernel_page_table = getActivePageTable();
}
