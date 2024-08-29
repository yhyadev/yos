//! An implementation of a round robin scheduling algorithm and an elf loader

const std = @import("std");

const arch = @import("arch.zig");
const higher_half = @import("higher_half.zig");
const vfs = @import("fs/vfs.zig");

const user_allocator = @import("memory.zig").user_allocator;

var backing_allocator: std.mem.Allocator = undefined;

pub var maybe_process: ?*Process = null;
var processes: std.ArrayListUnmanaged(Process) = .{};
var stopped_processes: std.ArrayListUnmanaged(*Process) = .{};
var process_queue: std.fifo.LinearFifo(*Process, .Dynamic) = undefined;

const reschedule_ticks = 0x19FBD0;

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
    env: std.StringHashMapUnmanaged([]const u8) = .{},
    argv: []const [*:0]const u8 = &.{},

    /// Allocate a new process into the list and return its pointer, reuses a stopped process place if there is any
    fn alloc(is_newly_allocated: *bool) std.mem.Allocator.Error!*Process {
        if (stopped_processes.popOrNull()) |stopped_process| {
            is_newly_allocated.* = false;

            return stopped_process;
        }

        is_newly_allocated.* = true;

        return processes.addOne(backing_allocator);
    }

    /// Load the elf segments and user stack, this modifies the context respectively
    fn loadElf(self: *Process, elf_content: []const u8) !void {
        const kernel_allocator = self.arena.allocator();

        var elf_exe_stream = std.io.fixedBufferStream(elf_content);

        const elf_header = std.elf.Header.read(&elf_exe_stream) catch return error.BadElf;

        var program_header_iterator = elf_header.program_header_iterator(&elf_exe_stream);

        while (program_header_iterator.next() catch return error.BadElf) |program_header| {
            switch (program_header.p_type) {
                std.elf.PT_NULL => {},

                std.elf.PT_NOTE => {},

                std.elf.PT_PHDR => {},

                std.elf.PT_LOAD => try mapElfSegment(self.page_table, kernel_allocator, elf_content, program_header),

                else => return error.BadElf,
            }
        }

        try mapUserStack(self.page_table, kernel_allocator);

        self.context.rcx = elf_header.entry;
        self.context.rsp = user_stack_top;
    }

    /// Map an elf segment into a specific page table with a specific allocator, this expects the segment to be aligned to 4096 (which is the minimum page size)
    fn mapElfSegment(page_table: *arch.paging.PageTable, allocator: std.mem.Allocator, elf_content: []const u8, program_header: std.elf.Elf64_Phdr) !void {
        const page_count = std.math.divCeil(usize, program_header.p_memsz, std.mem.page_size) catch unreachable;

        const pages = try allocator.allocWithOptions(u8, page_count * std.mem.page_size, std.mem.page_size, null);

        @memset(pages, 0);

        @memcpy(pages[0..program_header.p_filesz], elf_content[program_header.p_offset .. program_header.p_offset + program_header.p_filesz]);

        const pages_physical_address = page_table.physicalFromVirtual(@intFromPtr(pages.ptr)).?;

        for (0..page_count) |i| {
            const virtual_address = program_header.p_vaddr + i * std.mem.page_size;
            const physical_address = pages_physical_address + i * std.mem.page_size;

            try page_table.map(
                allocator,
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

    /// Map the user stack into a specific page table with a specific allocator
    fn mapUserStack(page_table: *arch.paging.PageTable, allocator: std.mem.Allocator) !void {
        const pages = try allocator.allocWithOptions(u8, user_stack_page_count * std.mem.page_size, std.mem.page_size, null);

        const pages_physical_address = page_table.physicalFromVirtual(@intFromPtr(pages.ptr)).?;

        for (0..user_stack_page_count) |i| {
            const virtual_address = user_stack_virtual_address + i * std.mem.page_size;
            const physical_address = pages_physical_address + i * std.mem.page_size;

            try page_table.map(
                allocator,
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
        if (fd >= self.files.items.len) return 0;

        if (self.files.items[fd]) |file| {
            return file.write(offset, buffer);
        }

        return 0;
    }

    /// Read from file using its index in the open files list
    pub fn readFile(self: *Process, fd: usize, offset: usize, buffer: []u8) usize {
        if (fd >= self.files.items.len) return 0;

        if (self.files.items[fd]) |file| {
            return file.read(offset, buffer);
        }

        return 0;
    }

    /// Read from directory using its index in the open files list
    pub fn readDir(self: *Process, fd: usize, offset: usize, buffer: []*vfs.FileSystem.Node) usize {
        if (fd >= self.files.items.len) return 0;

        if (self.files.items[fd]) |file| {
            if (file.tag != .directory) return 0;

            file.readDir(offset, buffer);

            return file.childCount() - offset;
        }

        return 0;
    }

    /// Add a child into the children list, reuses a stopped child place if there is any
    pub fn addChild(self: *Process, child: *Process) !usize {
        const kernel_allocator = self.arena.allocator();

        for (self.children.items, 0..) |*maybe_child, i| {
            if (maybe_child.* == null) {
                maybe_child.* = child;

                return @intCast(i);
            }
        }

        try self.children.append(kernel_allocator, child);

        return self.children.items.len - 1;
    }

    /// Add a file into the open files list, reuses a closed file place if there is any
    pub fn addFile(self: *Process, file: *vfs.FileSystem.Node) !usize {
        const kernel_allocator = self.arena.allocator();

        for (self.files.items, 0..) |*maybe_file, i| {
            if (maybe_file.* == null) {
                maybe_file.* = file;

                return i;
            }
        }

        try self.files.append(kernel_allocator, file);

        return self.files.items.len - 1;
    }

    /// Open a file and return its index in the open files list
    pub fn openFile(self: *Process, path: []const u8) !isize {
        const kernel_allocator = self.arena.allocator();

        const resolved_path = try std.fs.path.resolve(kernel_allocator, &.{ self.env.get("PWD").?, path });
        defer kernel_allocator.free(resolved_path);

        return @intCast(try self.addFile(try vfs.openAbsolute(resolved_path)));
    }

    /// Close a file using its index in the open files list
    pub fn closeFile(self: *Process, fd: usize) !void {
        if (fd >= self.files.items.len) return error.NotFound;

        if (self.files.items[fd]) |file| {
            self.files.items[fd] = null;

            return file.close();
        }

        return error.NotFound;
    }

    /// Put into the environment using a pair instead of key to value structure
    pub fn putEnvPair(self: *Process, env_pair: []const u8) !void {
        var env_pair_iterator = std.mem.splitSequence(u8, env_pair, "=");

        const env_key = env_pair_iterator.next() orelse return error.BadEnvPair;
        const env_value = env_pair_iterator.next() orelse return error.BadEnvPair;

        const kernel_allocator = self.arena.allocator();

        try self.env.put(kernel_allocator, env_key, env_value);
    }

    /// Put the default environment pairs
    fn putEnvDefaultPairs(self: *Process) std.mem.Allocator.Error!void {
        const kernel_allocator = self.arena.allocator();

        const home_path = try user_allocator.dupe(u8, "/home");
        const bin_path = try user_allocator.dupe(u8, "/usr/bin");

        try self.env.put(kernel_allocator, "HOME", home_path);
        try self.env.put(kernel_allocator, "PWD", home_path);

        try self.env.put(kernel_allocator, "PATH", bin_path);
    }

    /// Pass the control to underlying code that the process hold
    pub fn run(self: *Process) noreturn {
        self.page_table.setActivePageTable();

        self.putEnvDefaultPairs() catch |err| switch (err) {
            error.OutOfMemory => @panic("out of memory"),
        };

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

        stopped_processes.append(backing_allocator, self) catch |err| switch (err) {
            error.OutOfMemory => @panic("out of memory"),
        };

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
    var process_newly_allocated = false;

    const process = try Process.alloc(&process_newly_allocated);

    process.* = .{
        .id = if (process_newly_allocated) processes.items.len else process.id,
        .arena = std.heap.ArenaAllocator.init(backing_allocator),
        .context = .{},
        .page_table = undefined,
    };

    const kernel_allocator = process.arena.allocator();

    process.page_table = try arch.paging.PageTable.alloc(kernel_allocator);
    process.page_table.mapKernel();

    {
        const elf_file = try vfs.openAbsolute(elf_file_path);
        defer elf_file.close();

        const elf_content = try kernel_allocator.alloc(u8, elf_file.fileSize());

        _ = elf_file.read(0, elf_content);

        try process.loadElf(elf_content);
    }

    {
        const console_device = vfs.openAbsolute("/dev/console") catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NotFound => @panic("console device is not found"),
            else => unreachable,
        };

        try process.files.appendNTimes(kernel_allocator, console_device, 3);
    }

    maybe_process = process;
}

/// Kill a specific process by removing it from the list and the queue
pub fn kill(pid: usize) void {
    const process = &processes.items[pid - 1];

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
}

/// Spawn a new process while cloning its parent context
pub fn fork(context: *arch.cpu.process.Context) !usize {
    const parent_process = maybe_process.?;

    var child_process_newly_allocated = false;

    const child_process = try Process.alloc(&child_process_newly_allocated);

    child_process.* = .{
        .id = if (child_process_newly_allocated) processes.items.len else child_process.id,
        .arena = std.heap.ArenaAllocator.init(backing_allocator),
        .context = context.*,
        .page_table = undefined,
        .parent = parent_process,
    };

    child_process.context.rax = 0;

    const kernel_allocator = child_process.arena.allocator();

    child_process.page_table = try parent_process.page_table.clone(kernel_allocator);

    child_process.env = try parent_process.env.clone(kernel_allocator);

    child_process.files = try parent_process.files.clone(kernel_allocator);

    {
        try Process.mapUserStack(child_process.page_table, kernel_allocator);

        const StackPages = *[user_stack_page_count * std.mem.page_size]u8;

        const parent_stack_pages: StackPages = @ptrFromInt(higher_half.virtualFromPhysical(
            parent_process.page_table.physicalFromVirtual(user_stack_virtual_address).?,
        ));

        const child_stack_pages: StackPages = @ptrFromInt(higher_half.virtualFromPhysical(
            child_process.page_table.physicalFromVirtual(user_stack_virtual_address).?,
        ));

        @memcpy(child_stack_pages, parent_stack_pages);
    }

    _ = try parent_process.addChild(child_process);

    try process_queue.writeItem(child_process);

    return child_process.id;
}

/// Replace the current running context with a new context that is retrieved from an
/// elf file loaded from path in argv[0], and initialize the environment variables using
/// the provided list
pub fn execve(context: *arch.cpu.process.Context, argv: []const [*:0]const u8, envp: []const [*:0]const u8) !void {
    const process = maybe_process.?;

    const kernel_allocator = process.arena.allocator();

    if (argv.len < 1) return error.NotFound;

    const file_path = std.mem.span(argv[0]);

    var bin_path_iterator = std.mem.splitSequence(u8, process.env.get("PATH").?, ":");

    if (std.fs.path.isAbsolute(file_path)) {
        // A hacky way to only iterate on the root directory
        bin_path_iterator = std.mem.splitSequence(u8, "/", ".");
    }

    while (bin_path_iterator.next()) |bin_path| {
        const resolved_file_path = try std.fs.path.resolve(kernel_allocator, &.{ bin_path, file_path });
        defer kernel_allocator.free(resolved_file_path);

        const elf_file = vfs.openAbsolute(resolved_file_path) catch |err| switch (err) {
            error.NotFound => continue,
            inline else => |other_err| return other_err,
        };

        defer elf_file.close();

        const elf_content = try kernel_allocator.alloc(u8, elf_file.fileSize());

        _ = elf_file.read(0, elf_content);

        {
            const argv_on_heap = try user_allocator.alloc([*:0]const u8, argv.len);

            for (argv, 0..) |arg, i| {
                argv_on_heap[i] = try user_allocator.dupeZ(u8, std.mem.span(arg));
            }

            process.argv = argv_on_heap;
        }

        {
            for (envp) |env_pair_ptr| {
                try process.putEnvPair(try user_allocator.dupe(u8, std.mem.span(env_pair_ptr)));
            }
        }

        try process.loadElf(elf_content);

        context.* = process.context;

        return;
    }

    return error.NotFound;
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

        waiting_process.page_table.setActivePageTable();
    }
}

/// Must be called when the timer gives back control to the kernel
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
