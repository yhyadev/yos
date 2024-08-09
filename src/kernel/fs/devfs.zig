//! Device File System
//!
//! A file system but not file system, just a wrapper so you can implement a device read/write as a file

const std = @import("std");

const tty = @import("../tty.zig");
const vfs = @import("vfs.zig");

var backing_allocator: std.mem.Allocator = undefined;

var root: *vfs.FileSystem.Node = undefined;

pub var devices: std.ArrayListUnmanaged(vfs.FileSystem.Node) = .{};

pub const tty_device: vfs.FileSystem.Node = .{
    .name = "tty",
    .tag = .file,
    .vtable = &.{
        .write = struct {
            fn write(_: *vfs.FileSystem.Node, _: usize, buffer: []const u8) usize {
                tty.print("{s}", .{buffer});

                return buffer.len;
            }
        }.write,
    },
};

fn readDir(_: *vfs.FileSystem.Node, offset: u64, buffer: []*vfs.FileSystem.Node) void {
    for (offset..devices.items.len, 0..) |i, j| {
        if (j >= buffer.len) return;

        buffer[j] = &devices.items[i];
    }
}

fn childCount(_: *vfs.FileSystem.Node) usize {
    return devices.items.len;
}

pub fn init(allocator: std.mem.Allocator) vfs.FileSystem.Node.MountError!void {
    backing_allocator = allocator;

    try vfs.installFileSystem(.{ .name = "devfs" });

    root = try backing_allocator.create(vfs.FileSystem.Node);

    root.* = .{
        .name = "dev",
        .tag = .directory,
        .vtable = &.{
            .readDir = &readDir,
            .childCount = &childCount,
        },
    };

    try root.mount("/dev");

    try devices.append(backing_allocator, tty_device);
}
