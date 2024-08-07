const builtin = @import("builtin");

pub const target = builtin.cpu.arch;

const system = switch (target) {
    .x86_64 => @import("arch/x86_64.zig"),

    else => struct {},
};

pub const cpu = system.cpu;

pub const ioapic = switch (target) {
    .x86_64 => system.ioapic,

    else => struct {},
};

pub const lapic = switch (target) {
    .x86_64 => system.lapic,

    else => struct {},
};

pub const paging = system.paging;

pub fn init() void {
    system.init();
}
