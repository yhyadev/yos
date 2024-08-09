//! Tar File System
//!
//! A read-only file system which uses the standard tar implementation by Zig
//! This is intended to be used for initial ramdisk because the init ramdisk is a tar archive
//! that is loaded with the kernel by limine bootloader

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

var tar_file_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
var tar_link_name_buffer: [std.fs.max_path_bytes]u8 = undefined;

const MountError = vfs.FileSystem.Node.MountError || CreateError;

pub fn mount(path: []const u8, tar_data: []u8) MountError!void {
    const directory = try directories.addOne(backing_allocator);

    directory.* = .{
        .node = .{
            .name = std.fs.path.basename(path),
            .tag = .directory,
            .ctx = directory,
            .vtable = &Directory.vtable,
        },
    };

    try directory.node.mount(path);

    var tar_file_stream = std.io.fixedBufferStream(tar_data);

    var tar_iterator = std.tar.iterator(tar_file_stream.reader(), .{
        .file_name_buffer = &tar_file_name_buffer,
        .link_name_buffer = &tar_link_name_buffer,
    });

    while (tar_iterator.next() catch @panic("could not parse tar file")) |tar_entry| {
        switch (tar_entry.kind) {
            .file => try createFile(path, tar_entry.name, tar_entry.size, tar_entry.reader()),
            .directory => try createDirectory(path, tar_entry.name),

            .sym_link => @panic("symbolic links should not be in the tar file"),
        }
    }
}

const CreateError = vfs.OpenAbsoluteError;

fn createFile(cwd: []const u8, path: []const u8, size: u64, reader: anytype) CreateError!void {
    const resolved_path = try std.fs.path.resolve(backing_allocator, &.{ cwd, path });

    const parent_path = std.fs.path.dirname(resolved_path) orelse "/";
    const parent_node = try vfs.openAbsolute(parent_path);
    const parent_directory: *Directory = @ptrCast(@alignCast(parent_node.ctx));

    const child_node = try parent_directory.children.addOne(backing_allocator);

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
        .name = std.fs.path.basename(path),
        .tag = .file,
        .ctx = @ptrCast(@alignCast(content_on_heap)),
        .vtable = &File.vtable,
    };
}

fn createDirectory(cwd: []const u8, path: []const u8) CreateError!void {
    // The root file is already created
    if (std.mem.eql(u8, path, "./")) return;

    const resolved_path = try std.fs.path.resolve(backing_allocator, &.{ cwd, path });

    const parent_path = std.fs.path.dirname(resolved_path) orelse "/";
    const parent_node = try vfs.openAbsolute(parent_path);
    const parent_directory: *Directory = @ptrCast(@alignCast(parent_node.ctx));

    const child_node = try parent_directory.children.addOne(backing_allocator);

    const child_directory = try directories.addOne(backing_allocator);
    child_directory.* = .{ .node = undefined };

    child_node.* = .{
        .name = std.fs.path.basename(path),
        .tag = .directory,
        .ctx = child_directory,
        .vtable = &Directory.vtable,
    };
}

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
    backing_allocator = allocator;

    try vfs.installFileSystem(.{ .name = "tarfs" });
}
