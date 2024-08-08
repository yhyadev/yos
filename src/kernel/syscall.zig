const arch = @import("arch.zig");
const scheduler = @import("scheduler.zig");

pub fn exit(context: *arch.cpu.process.Context, status: usize) void {
    _ = status;

    scheduler.kill(scheduler.maybe_process.?.id);

    scheduler.reschedule(context) catch @panic("out of memory");
}
