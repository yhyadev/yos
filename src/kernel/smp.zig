const limine = @import("limine");

const arch = @import("arch.zig");

export var smp_request: limine.SmpRequest = .{};

var core_info_buffer: [max_core_count]arch.cpu.core.Info = undefined;

pub var core_count: u64 = undefined;
pub const max_core_count = 255;

pub var bootstrap_lapic_id: u32 = undefined;

pub fn init(comptime jumpPoint: *const fn () noreturn) noreturn {
    const maybe_smp_response = smp_request.response;

    if (maybe_smp_response == null) {
        @panic("could not retrieve information about the cpu");
    }

    const smp_response = maybe_smp_response.?;

    core_count = smp_response.cpu_count;

    if (arch.target.isX86()) {
        bootstrap_lapic_id = smp_response.bsp_lapic_id;
    }

    if (core_count > max_core_count) {
        @panic("the amount of cores exceeded the max");
    }

    const lambda = struct {
        fn startCore(raw_core_info: *limine.SmpInfo) callconv(.C) noreturn {
            arch.cpu.registers.ModelSpecific.write(.kernel_gs_base, raw_core_info.processor_id);

            jumpPoint();
        }
    };

    for (smp_response.cpus()) |raw_core_info| {
        core_info_buffer[raw_core_info.processor_id].id = raw_core_info.processor_id;

        arch.cpu.core.Info.write(&core_info_buffer[raw_core_info.processor_id]);

        if (raw_core_info.processor_id != 0) {
            @atomicStore(@TypeOf(raw_core_info.goto_address), &raw_core_info.goto_address, &lambda.startCore, .monotonic);
        }
    }

    jumpPoint();
}
