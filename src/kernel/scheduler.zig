//! Scheduler
//!
//! An implementation of a round robin scheduling algorithm and an elf loader

const std = @import("std");

const arch = @import("arch.zig");
const vfs = @import("fs/vfs.zig");

var backing_allocator: std.mem.Allocator = undefined;

var maybe_process: ?*Process = null;
var processes: std.ArrayListUnmanaged(Process) = .{};
var process_queue: std.fifo.LinearFifo(*Process, .Dynamic) = undefined;

const reschedule_ticks = 0x1000000;

const user_stack_page_count = 16;
const user_stack_virtual_address = 0x10002000;
const user_stack_top = user_stack_virtual_address + user_stack_page_count * std.mem.page_size;

/// A currently running or idle process
const Process = struct {
    id: u64,
    context: arch.cpu.process.Context,
    page_table: *arch.paging.PageTable,
    arena: std.heap.ArenaAllocator,

    /// Load the elf segments and user stack, this modifies the context respectively
    fn loadElf(self: *Process, elf_content: []const u8) !void {
        const scoped_allocator = self.arena.allocator();

        var elf_exe_stream = std.io.fixedBufferStream(elf_content);

        const elf_header = std.elf.Header.read(&elf_exe_stream) catch return error.BadElf;

        var program_header_iterator = elf_header.program_header_iterator(&elf_exe_stream);

        while (program_header_iterator.next() catch return error.BadElf) |program_header| {
            switch (program_header.p_type) {
                std.elf.PT_NULL => {},

                std.elf.PT_PHDR => {},

                std.elf.PT_LOAD => try mapElfSegment(scoped_allocator, self.page_table, elf_content, program_header),

                else => return error.BadElf,
            }
        }

        try mapUserStack(scoped_allocator, self.page_table);

        self.context.rcx = elf_header.entry;
        self.context.rsp = user_stack_top;
    }

    /// Map an elf segment into a specific page table with a specific scoped allocator, this expects the segment to be aligned to 4096 (which is the minimum page size)
    fn mapElfSegment(scoped_allocator: std.mem.Allocator, page_table: *arch.paging.PageTable, elf_content: []const u8, program_header: std.elf.Elf64_Phdr) !void {
        if (program_header.p_filesz != program_header.p_memsz) return error.BadElf;

        const page_count = std.math.divCeil(usize, program_header.p_filesz, std.mem.page_size) catch unreachable;

        const pages = try scoped_allocator.allocWithOptions(u8, page_count * std.mem.page_size, std.mem.page_size, null);
        @memcpy(pages[0..program_header.p_filesz], elf_content[program_header.p_offset .. program_header.p_offset + program_header.p_filesz]);

        for (0..page_count) |i| {
            const virtual_address = program_header.p_vaddr + i * std.mem.page_size;
            const physical_address = arch.paging.physicalFromVirtual(page_table, @intFromPtr(pages.ptr)).? + i * std.mem.page_size;

            try arch.paging.mapPage(
                scoped_allocator,
                page_table,
                virtual_address,
                physical_address,
                .{
                    .user = true,
                    .global = false,
                    .writable = (program_header.p_flags & std.elf.PF_W) != 0,
                    .executable = (program_header.p_flags & std.elf.PF_X) != 0,
                },
            );
        }
    }

    /// Map the user stack into a specific page table with a specific scoped allocator
    fn mapUserStack(scoped_allocator: std.mem.Allocator, page_table: *arch.paging.PageTable) !void {
        const user_stack_pages = try scoped_allocator.allocWithOptions(u8, user_stack_page_count * std.mem.page_size, std.mem.page_size, null);

        for (0..user_stack_page_count) |i| {
            const virtual_address = user_stack_virtual_address + i * std.mem.page_size;
            const physical_address = arch.paging.physicalFromVirtual(page_table, @intFromPtr(user_stack_pages.ptr)).? + i * std.mem.page_size;

            try arch.paging.mapPage(scoped_allocator, page_table, virtual_address, physical_address, .{
                .user = true,
                .global = false,
                .writable = true,
                .executable = false,
            });
        }
    }

    /// Pass the control to underlying code that the process hold
    pub fn run(self: Process) noreturn {
        arch.paging.setActivePageTable(self.page_table);

        if (arch.target.isX86()) {
            asm volatile ("sysretq"
                :
                : [entry] "{rcx}" (self.context.rcx),
                  [flags] "{r11}" (0x202),
                  [stack_top] "{rsp}" (self.context.rsp),
                : "memory"
            );

            unreachable;
        }
    }
};

/// Set the initial process, which is necessary before starting the scheduler if there is no processes before this
pub fn setInitialProcess(elf_file_path: []const u8) !void {
    maybe_process = try processes.addOne(backing_allocator);

    maybe_process.?.* = .{
        .id = processes.items.len,
        .context = .{},
        .page_table = undefined,
        .arena = std.heap.ArenaAllocator.init(backing_allocator),
    };

    const scoped_allocator = maybe_process.?.arena.allocator();

    maybe_process.?.page_table = try arch.paging.allocPageTable(scoped_allocator);

    const elf_file = try vfs.openAbsolute(elf_file_path);
    defer elf_file.close();

    const elf_content = try scoped_allocator.alloc(u8, elf_file.fileSize());

    _ = elf_file.read(0, elf_content);

    try maybe_process.?.loadElf(elf_content);
}

/// Control the timer interrupt manually using the rescheduler ticks specified
inline fn oneshot() void {
    if (arch.target.isX86()) {
        arch.lapic.getLapic().oneshot(arch.cpu.interrupts.offset(0), @truncate(reschedule_ticks));
    }
}

/// Reschedule processes, this assumes the timer gave control to the kernel
fn reschedule(context: *arch.cpu.process.Context) std.mem.Allocator.Error!void {
    // If there is no running process and the process queue is empty, don't do anything
    if (maybe_process == null and process_queue.readableLength() == 0) return;

    // If there is a running process
    if (maybe_process) |process| {
        // Update the context
        process.context = context.*;

        // If the process queue is not empty, add the currently running process into the queue
        if (process_queue.readableLength() > 0) {
            try process_queue.writeItem(process);
        }
    }

    // If there is a process in the queue, do a context switch and set the currently running process
    if (process_queue.readItem()) |process| {
        maybe_process = process;

        context.* = process.context;
    }

    // Now change the active page table to the currently running process's page table
    arch.paging.setActivePageTable(maybe_process.?.page_table);
}

/// Called when the Timer gives back control to the kernel
fn interrupt(context: *arch.cpu.process.Context) callconv(.C) void {
    defer arch.cpu.interrupts.end();

    reschedule(context) catch @panic("out of memory");

    oneshot();
}

/// Start scheduling processes and join user-space
/// Note: Ensure that you set an initial process before calling this
pub fn start() noreturn {
    std.debug.assert(maybe_process != null);

    arch.cpu.interrupts.handle(0, &interrupt);

    oneshot();

    maybe_process.?.run();
}

pub fn init(allocator: std.mem.Allocator) void {
    backing_allocator = allocator;

    process_queue = std.fifo.LinearFifo(*Process, .Dynamic).init(backing_allocator);
}
