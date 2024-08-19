//! Temporary File System
//!
//! A file system that only lives on the ram stick and therefore would be gone instantly
//! after rebooting

const std = @import("std");

const vfs = @import("vfs.zig");

var backing_allocator: std.mem.Allocator = undefined;

var directories: std.ArrayListUnmanaged(Directory) = .{};

const Directory = struct {
    node: vfs.FileSystem.Node,
    children: std.ArrayListUnmanaged(vfs.FileSystem.Node) = .{},

    const vtable: vfs.FileSystem.Node.VTable = .{
        .readDir = struct {
            fn readDir(node: *vfs.FileSystem.Node, offset: u64, buffer: []*vfs.FileSystem.Node) void {
                const directory: *Directory = @ptrCast(@alignCast(node.ctx));

                for (offset..directory.children.items.len, 0..) |i, j| {
                    if (j >= buffer.len) return;

                    buffer[j] = &directory.children.items[i];
                }
            }
        }.readDir,

        .childCount = struct {
            fn childCount(node: *vfs.FileSystem.Node) usize {
                const directory: *Directory = @ptrCast(@alignCast(node.ctx));

                return directory.children.items.len;
            }
        }.childCount,
    };
};

const File = struct {
    const vtable: vfs.FileSystem.Node.VTable = .{
        .write = struct {
            fn write(node: *vfs.FileSystem.Node, offset: u64, buffer: []const u8) u64 {
                const content: *[]u8 = @ptrCast(@alignCast(node.ctx));

                var written: usize = 0;

                if (offset >= content.len or buffer.len > content.len - offset) {
                    const new_content_len = content.len + offset + buffer.len;

                    if (!backing_allocator.resize(content.*, new_content_len)) {
                        content.* = backing_allocator.realloc(content.*, new_content_len) catch |err| switch (err) {
                            error.OutOfMemory => @panic("out of memory"),
                        };
                    }
                }

                for (offset..content.len, 0..) |i, j| {
                    if (j >= content.len) return written;

                    content.*[i] = buffer[j];

                    written += 1;
                }

                return written;
            }
        }.write,

        .read = struct {
            fn read(node: *vfs.FileSystem.Node, offset: u64, buffer: []u8) u64 {
                const content: *[]u8 = @ptrCast(@alignCast(node.ctx));

                if (offset > content.len) return 0;

                for (offset..content.len, 0..) |i, j| {
                    if (j >= buffer.len) return buffer.len;

                    buffer[j] = content.*[i];
                }

                return content.len - offset;
            }
        }.read,

        .fileSize = struct {
            fn fileSize(node: *vfs.FileSystem.Node) usize {
                const content: *[]u8 = @ptrCast(@alignCast(node.ctx));

                return content.len;
            }
        }.fileSize,
    };
};

const MakeError = error{AlreadyExists} || vfs.OpenAbsoluteError;

pub fn makeFile(cwd: []const u8, path: []const u8, size: u64, reader: anytype) MakeError!void {
    const resolved_path = try std.fs.path.resolve(backing_allocator, &.{ cwd, path });

    const parent_path = std.fs.path.dirname(resolved_path) orelse "/";
    const parent_node = try vfs.openAbsolute(parent_path);
    const parent_directory: *Directory = @ptrCast(@alignCast(parent_node.ctx));

    for (parent_directory.children.items) |child_node| {
        if (std.mem.eql(u8, child_node.name, std.fs.path.basename(path))) {
            return error.AlreadyExists;
        }
    }

    const child_node = try parent_directory.children.addOne(backing_allocator);

    const name = std.fs.path.basename(path);
    const name_on_heap = try backing_allocator.dupe(u8, name);

    // Uses indirection because Zig slices contain the length with them
    const content_on_heap = try backing_allocator.create([]u8);

    if (size != 0) {
        const content = try backing_allocator.alloc(u8, size);

        _ = try reader.readAll(content);

        content_on_heap.* = content;
    } else {
        content_on_heap.* = "";
    }

    child_node.* = .{
        .name = name_on_heap,
        .tag = .file,
        .ctx = @ptrCast(@alignCast(content_on_heap)),
        .vtable = &File.vtable,
    };
}

pub fn makeDirectory(cwd: []const u8, path: []const u8) MakeError!void {
    const resolved_path = try std.fs.path.resolve(backing_allocator, &.{ cwd, path });

    const parent_path = std.fs.path.dirname(resolved_path) orelse "/";
    const parent_node = try vfs.openAbsolute(parent_path);
    const parent_directory: *Directory = @ptrCast(@alignCast(parent_node.ctx));

    for (parent_directory.children.items) |child_node| {
        if (std.mem.eql(u8, child_node.name, std.fs.path.basename(path))) {
            return error.AlreadyExists;
        }
    }

    const child_node = try parent_directory.children.addOne(backing_allocator);

    const child_directory = try directories.addOne(backing_allocator);
    child_directory.* = .{ .node = undefined };

    const name = std.fs.path.basename(path);
    const name_on_heap = try backing_allocator.dupe(u8, name);

    child_node.* = .{
        .name = name_on_heap,
        .tag = .directory,
        .ctx = child_directory,
        .vtable = &Directory.vtable,
    };
}

pub fn makeHierarchicalTree() MakeError!void {
    try makeDirectory("/", "./home");
    try makeDirectory("/", "./tmp");
    try makeDirectory("/", "./etc");

    try makeDirectory("/", "./usr");
    try makeDirectory("/usr", "./bin");
    try makeDirectory("/usr", "./lib");
}

/// Support for unpacking a tar file into the temporary file system
pub const tar = struct {
    var file_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var link_name_buffer: [std.fs.max_path_bytes]u8 = undefined;

    const UnpackError = vfs.OpenAbsoluteError;

    pub fn unpack(path: []const u8, tar_data: []u8) UnpackError!void {
        var tar_file_stream = std.io.fixedBufferStream(tar_data);

        var tar_iterator = std.tar.iterator(tar_file_stream.reader(), .{
            .file_name_buffer = &file_name_buffer,
            .link_name_buffer = &link_name_buffer,
        });

        while (tar_iterator.next() catch @panic("could not parse tar file")) |tar_entry| {
            switch (tar_entry.kind) {
                .file => makeFile(path, tar_entry.name, tar_entry.size, tar_entry.reader()) catch |err| switch (err) {
                    error.AlreadyExists => {},
                    inline else => |other_err| return other_err,
                },

                .directory => makeDirectory(path, tar_entry.name) catch |err| switch (err) {
                    error.AlreadyExists => {},
                    inline else => |other_err| return other_err,
                },

                .sym_link => @panic("symbolic links should not be in the tar file"),
            }
        }
    }
};

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
    backing_allocator = allocator;

    const root = try directories.addOne(backing_allocator);

    root.* = .{
        .node = .{
            .name = "",
            .tag = .directory,
            .ctx = root,
            .vtable = &Directory.vtable,
        },
    };

    root.node.mount("/") catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,

        else => unreachable,
    };

    try vfs.installFileSystem(.{ .name = "tmpfs" });
}
