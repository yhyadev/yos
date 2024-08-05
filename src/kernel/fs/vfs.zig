//! Virtual File System
//!
//! The abstract features of a file system

const std = @import("std");

var backing_allocator: std.mem.Allocator = undefined;

var installed_file_systems: std.ArrayListUnmanaged(FileSystem) = .{};

var root: *FileSystem.Node = undefined;

var mount_points: std.StringHashMapUnmanaged(*FileSystem.Node) = .{};

/// An interface representing a file system
pub const FileSystem = struct {
    /// What is the name of this file system?
    name: []const u8,

    /// A file or a directory, basically a node in the file system
    pub const Node = struct {
        /// What is the name of this node?
        name: []const u8,
        /// What does this node represent? is it a file or a directory
        tag: Tag,
        /// Implementation-defined pointer
        ctx: ?*anyopaque = null,
        /// Table of the features of the node
        vtable: *const VTable,

        pub const VTable = struct {
            open: ?*const fn (node: *Node) void = null,
            close: ?*const fn (node: *Node) void = null,
            read: ?*const fn (node: *Node, offset: u64, buffer: []u8) usize = null,
            write: ?*const fn (node: *Node, offset: u64, buffer: []const u8) usize = null,
            readDir: ?*const fn (node: *Node, offset: u64, buffer: []*Node) void = null,
            fileSize: ?*const fn (node: *Node) usize = null,
            childCount: ?*const fn (node: *Node) usize = null,
        };

        pub const Tag = enum {
            file,
            directory,
        };

        /// Open the underlying file or directory
        pub fn open(self: *Node) void {
            if (self.vtable.open) |openImpl| {
                openImpl(self);
            }
        }

        /// Close the underlying file or directory
        pub fn close(self: *Node) void {
            if (self.vtable.close) |closeImpl| {
                closeImpl(self);
            }
        }

        /// Read from the underlying file
        pub fn read(self: *Node, offset: u64, buffer: []u8) usize {
            if (self.tag == .directory) return 0;

            if (self.vtable.read) |readImpl| {
                return readImpl(self, offset, buffer);
            }

            return 0;
        }

        /// Write into the underlying file
        pub fn write(self: *Node, offset: u64, buffer: []const u8) usize {
            if (self.tag == .directory) return 0;

            if (self.vtable.write) |writeImpl| {
                return writeImpl(self, offset, buffer);
            }

            return 0;
        }

        /// Read from the underlying directory
        pub fn readDir(self: *Node, offset: u64, buffer: []*Node) void {
            if (self.tag == .file) return;

            if (self.vtable.readDir) |readDirImpl| {
                readDirImpl(self, offset, buffer);
            }
        }

        /// Get the amount of bytes in the underlying file
        pub fn fileSize(self: *Node) usize {
            if (self.tag == .directory) return 0;

            if (self.vtable.fileSize) |fileSizeImpl| {
                return fileSizeImpl(self);
            }

            return 0;
        }

        /// Get the count of children in the underlying directory
        pub fn fileCount(self: *Node) usize {
            if (self.tag == .file) return 0;

            if (self.vtable.childCount) |childCountImpl| {
                return childCountImpl(self);
            }

            return 0;
        }

        pub const MountError = error{ PathNotAbsolute, PathNotNormalized } || std.mem.Allocator.Error;

        /// Redirect any use of the path provided to this node
        pub fn mount(self: *Node, path: []const u8) MountError!void {
            if (!std.fs.path.isAbsolute(path)) return error.PathNotAbsolute;
            if (path.len > 1 and path[path.len - 1] == '/') return error.PathNotNormalized;

            try mount_points.put(backing_allocator, path, self);
        }
    };
};

/// Installs the file system to be known in the future
pub fn installFileSystem(file_system: FileSystem) std.mem.Allocator.Error!void {
    try installed_file_systems.append(backing_allocator, file_system);
}

pub const UnmountError = error{ PathNotAbsolute, PathNotNormalized };

/// Remove the mount point from the list (which stops redirecting the path)
pub fn unmount(path: []const u8) UnmountError!void {
    if (!std.fs.path.isAbsolute(path)) return error.PathNotAbsolute;
    if (path.len > 1 and path[path.len - 1] == '/') return error.PathNotNormalized;

    _ = mount_points.remove(path);
}

pub const OpenError = error{ NotFound, NotDirectory };

pub const OpenAbsoluteError = error{PathNotAbsolute} || OpenError || std.mem.Allocator.Error;

/// Open the node using an absolute path and return the opened node
pub fn openAbsolute(path: []const u8) OpenAbsoluteError!*FileSystem.Node {
    if (!std.fs.path.isAbsolute(path)) return error.PathNotAbsolute;

    var node = root;

    if (mount_points.get("/")) |mount_point| {
        node = mount_point;
    }

    var path_component_iterator = try std.fs.path.componentIterator(path);

    while (path_component_iterator.next()) |path_component| {
        switch (node.tag) {
            .file => return error.NotDirectory,

            .directory => {
                if (mount_points.get(path_component.path)) |mount_point| {
                    node = mount_point;

                    continue;
                }

                const file_count = node.fileCount();

                if (file_count == 0) return error.NotFound;

                const files = try backing_allocator.alloc(*FileSystem.Node, file_count);
                defer backing_allocator.free(files);

                node.readDir(0, files);

                var found_file = false;

                for (files) |file| {
                    if (std.mem.eql(u8, file.name, path_component.name)) {
                        node = file;
                        found_file = true;

                        break;
                    }
                }

                if (!found_file) return error.NotFound;
            },
        }
    }

    node.open();

    return node;
}

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
    backing_allocator = allocator;

    root = try backing_allocator.create(FileSystem.Node);

    root.* = .{
        .name = "",
        .tag = .directory,
        .vtable = &.{},
    };
}
