//! Scheduler
//!
//! An implementation of a round robin scheduling algorithm and an elf loader

const std = @import("std");

const arch = @import("arch.zig");
const vfs = @import("fs/vfs.zig");

var backing_allocator: std.mem.Allocator = undefined;

pub var maybe_process: ?*Process = null;
var processes: std.ArrayListUnmanaged(Process) = .{};
var process_queue: std.fifo.LinearFifo(*Process, .Dynamic) = undefined;

const reschedule_ticks = 0x100000;

const user_stack_page_count = 16;
const user_stack_virtual_address = 0x10002000;
const user_stack_top = user_stack_virtual_address + user_stack_page_count * std.mem.page_size;

/// A currently running or idle process
const Process = struct {
    id: usize,
    arena: std.heap.ArenaAllocator,
    context: arch.cpu.process.Context,
    page_table: *arch.paging.PageTable,
    parent: ?*Process = null,
    children: std.ArrayListUnmanaged(?*Process) = .{},
    files: std.ArrayListUnmanaged(?*vfs.FileSystem.Node) = .{},

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

                std.elf.PT_LOAD => try mapElfSegment(self.page_table, scoped_allocator, elf_content, program_header),

                else => return error.BadElf,
            }
        }

        try mapUserStack(self.page_table, scoped_allocator);

        self.context.rcx = elf_header.entry;
        self.context.rsp = user_stack_top;
    }

    /// Map an elf segment into a specific page table with a specific scoped allocator, this expects the segment to be aligned to 4096 (which is the minimum page size)
    fn mapElfSegment(page_table: *arch.paging.PageTable, scoped_allocator: std.mem.Allocator, elf_content: []const u8, program_header: std.elf.Elf64_Phdr) !void {
        if (program_header.p_filesz != program_header.p_memsz) return error.BadElf;

        const page_count = std.math.divCeil(usize, program_header.p_filesz, std.mem.page_size) catch unreachable;

        const pages = try scoped_allocator.allocWithOptions(u8, page_count * std.mem.page_size, std.mem.page_size, null);

        @memcpy(pages[0..program_header.p_filesz], elf_content[program_header.p_offset .. program_header.p_offset + program_header.p_filesz]);

        for (0..page_count) |i| {
            const virtual_address = program_header.p_vaddr + i * std.mem.page_size;
            const physical_address = page_table.physicalFromVirtual(@intFromPtr(pages.ptr)).? + i * std.mem.page_size;

            try page_table.map(
                scoped_allocator,
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
    fn mapUserStack(page_table: *arch.paging.PageTable, scoped_allocator: std.mem.Allocator) !void {
        const user_stack_pages = try scoped_allocator.allocWithOptions(u8, user_stack_page_count * std.mem.page_size, std.mem.page_size, null);

        for (0..user_stack_page_count) |i| {
            const virtual_address = user_stack_virtual_address + i * std.mem.page_size;
            const physical_address = page_table.physicalFromVirtual(@intFromPtr(user_stack_pages.ptr)).? + i * std.mem.page_size;

            try page_table.map(
                scoped_allocator,
                virtual_address,
                physical_address,
                .{
                    .user = true,
                    .global = false,
                    .writable = true,
                    .executable = false,
                },
            );
        }
    }

    /// Write into file using its index in the open files list
    pub fn writeFile(self: *Process, fd: usize, offset: usize, buffer: []const u8) usize {
        if (fd > self.files.items.len) return 0;

        if (self.files.items[fd]) |file| {
            return file.write(offset, buffer);
        }

        return 0;
    }

    /// Read from file using its index in the open files list
    pub fn readFile(self: *Process, fd: usize, offset: usize, buffer: []u8) usize {
        if (fd > self.files.items.len) return 0;

        if (self.files.items[fd]) |file| {
            return file.read(offset, buffer);
        }

        return 0;
    }

    /// Open a file and return its index in the open files list
    pub fn openFile(self: *Process, path: []const u8) !isize {
        // TODO: Currently working dirctory should be used here
        const resolved_path = try std.fs.path.resolve(backing_allocator, &.{ "/", path });

        const file = try vfs.openAbsolute(resolved_path);

        try self.files.append(backing_allocator, file);

        return @intCast(self.files.items.len - 1);
    }

    /// Close a file using its index in the open files list
    pub fn closeFile(self: *Process, fd: usize) !void {
        if (fd > self.files.items.len) return error.NotFound;

        if (self.files.items[fd]) |file| {
            self.files.items[fd] = null;

            return file.close();
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

    /// Stop the process from running and free resources
    pub fn stop(self: *Process) void {
        if (maybe_process == self) {
            maybe_process = null;
        }

        for (process_queue.readableSlice(0), 0..) |waiting_process, i| {
            if (waiting_process == self) {
                for (0..i) |_| {
                    process_queue.writeItem(process_queue.readItem().?) catch unreachable;
                }

                _ = process_queue.readItem().?;
            }
        }

        for (self.files.items) |maybe_file| {
            if (maybe_file) |file| {
                file.close();
            }
        }

        self.arena.deinit();
    }
};

/// Set the initial process, which is necessary before starting the scheduler if there is no processes before this
pub fn setInitialProcess(elf_file_path: []const u8) !void {
    const process = try processes.addOne(backing_allocator);

    process.* = .{
        .id = processes.items.len,
        .arena = std.heap.ArenaAllocator.init(backing_allocator),
        .context = .{},
        .page_table = undefined,
    };

    const scoped_allocator = process.arena.allocator();

    process.page_table = try arch.paging.PageTable.init(scoped_allocator);
    process.page_table.mapKernel();

    {
        const elf_file = try vfs.openAbsolute(elf_file_path);
        defer elf_file.close();

        const elf_content = try scoped_allocator.alloc(u8, elf_file.fileSize());

        _ = elf_file.read(0, elf_content);

        try process.loadElf(elf_content);
    }

    {
        const console_device = vfs.openAbsolute("/dev/console") catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.NotFound => @panic("console device is not found"),

            else => unreachable,
        };

        try process.files.appendNTimes(scoped_allocator, console_device, 3);
    }

    maybe_process = process;
}

/// Kill a specific process by removing it from the list and the queue, also it deallocates all memory it consumed
pub fn kill(pid: usize) void {
    for (processes.items) |*process| {
        if (process.id == pid) {
            process.stop();

            if (process.parent) |parent_process| {
                for (parent_process.children.items) |*maybe_child| {
                    if (maybe_child.* == process) {
                        maybe_child.* = null;
                    }
                }
            }

            for (process.children.items) |maybe_child| {
                if (maybe_child) |child| {
                    kill(child.id);
                }
            }

            break;
        }
    }
}

/// Spawn a new process while cloning its parent context
pub fn fork(context: *arch.cpu.process.Context) !usize {
    const parent_process = maybe_process.?;

    const child_process = try processes.addOne(backing_allocator);

    child_process.* = .{
        .id = processes.items.len,
        .arena = std.heap.ArenaAllocator.init(backing_allocator),
        .context = context.*,
        .page_table = undefined,
    };

    child_process.context.rax = 0;

    const scoped_allocator = child_process.arena.allocator();

    child_process.page_table = try parent_process.page_table.dupe(scoped_allocator);

    {
        try Process.mapUserStack(child_process.page_table, scoped_allocator);

        const StackPages = *[user_stack_page_count * std.mem.page_size]u8;

        const parent_stack_pages: StackPages = @ptrFromInt(arch.paging.virtualFromPhysical(
            parent_process.page_table.physicalFromVirtual(user_stack_virtual_address).?,
        ));

        const child_stack_pages: StackPages = @ptrFromInt(arch.paging.virtualFromPhysical(
            child_process.page_table.physicalFromVirtual(user_stack_virtual_address).?,
        ));

        @memcpy(child_stack_pages, parent_stack_pages);
    }

    {
        const console_device = vfs.openAbsolute("/dev/console") catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,

            else => unreachable,
        };

        try child_process.files.appendNTimes(scoped_allocator, console_device, 3);
    }

    try parent_process.children.append(parent_process.arena.allocator(), child_process);

    try process_queue.writeItem(child_process);

    return child_process.id;
}

/// Replace the current running context with a new context that is retrieved from an
/// elf file loaded from path in argv[0]
pub fn execv(context: *arch.cpu.process.Context, argv: []const [*:0]const u8) !void {
    const process = maybe_process.?;

    const scoped_allocator = process.arena.allocator();

    if (argv.len < 1) return error.NotFound;

    const elf_file_path = std.mem.span(argv[0]);

    {
        const elf_file = try vfs.openAbsolute(elf_file_path);
        defer elf_file.close();

        const elf_content = try scoped_allocator.alloc(u8, elf_file.fileSize());

        _ = elf_file.read(0, elf_content);

        try process.loadElf(elf_content);
    }

    process.files.clearRetainingCapacity();

    {
        const console_device = vfs.openAbsolute("/dev/console") catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.NotFound => @panic("console device is not found"),

            else => unreachable,
        };

        try process.files.appendNTimes(scoped_allocator, console_device, 3);
    }

    context.* = process.context;
}

/// Control the timer interrupt manually using the ticks specified
inline fn oneshot(ticks: usize) void {
    if (arch.target.isX86()) {
        arch.lapic.getLapic().oneshot(arch.cpu.interrupts.offset(0), @truncate(ticks));
    }
}

/// Reschedule processes, this assumes the timer gave control to the kernel
pub fn reschedule(context: *arch.cpu.process.Context) std.mem.Allocator.Error!void {
    if (maybe_process == null and process_queue.readableLength() == 0) {
        while (true) {}
    }

    if (process_queue.readItem()) |waiting_process| {
        if (maybe_process) |running_process| {
            running_process.context = context.*;

            try process_queue.writeItem(running_process);
        }

        maybe_process = waiting_process;

        context.* = waiting_process.context;

        arch.paging.setActivePageTable(waiting_process.page_table);
    }
}

/// Called when the timer gives back control to the kernel
fn interrupt(context: *arch.cpu.process.Context) callconv(.C) void {
    defer arch.cpu.interrupts.end();

    reschedule(context) catch @panic("out of memory");

    oneshot(reschedule_ticks);
}

/// Start scheduling processes and join user-space
/// Note: Ensure that you set an initial process before calling this
pub fn start() noreturn {
    std.debug.assert(maybe_process != null);

    arch.cpu.interrupts.handle(0, &interrupt);

    oneshot(reschedule_ticks);

    maybe_process.?.run();
}

pub fn init(allocator: std.mem.Allocator) void {
    backing_allocator = allocator;

    process_queue = std.fifo.LinearFifo(*Process, .Dynamic).init(backing_allocator);
}
