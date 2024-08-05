const std = @import("std");
const limine = @import("limine");

const tarfs = @import("fs/tarfs.zig");
const vfs = @import("fs/vfs.zig");

export var module_request: limine.ModuleRequest = .{};

pub fn init() void {
    const maybe_module_response = module_request.response;

    if (maybe_module_response == null) {
        @panic("could not retrieve information about the limine modules");
    }

    const module_response = module_request.response.?;

    var initrd_module: *limine.File = undefined;

    var found_initrd = false;

    for (module_response.modules()) |module| {
        if (std.mem.eql(u8, std.mem.span(module.cmdline), "initrd")) {
            initrd_module = module;
            found_initrd = true;

            break;
        }
    }

    if (!found_initrd) {
        @panic("could not find init ramdisk in limine modules");
    }

    tarfs.mount("/initrd", initrd_module.data()) catch @panic("could not mount the init ramdisk");
}
