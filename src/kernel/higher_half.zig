//! Higher half
//!
//! A utility for our higher half kernel, includes the offset to map physical to virtual memory
//! which is called higher half direct map offset

const limine = @import("limine");

export var hhdm_request: limine.HhdmRequest = .{};

pub var hhdm_offset: usize = undefined;

pub fn init() void {
    const maybe_hhdm_response = hhdm_request.response;

    if (maybe_hhdm_response == null) {
        @panic("could not retrieve information about the higher half kernel");
    }

    const hhdm_response = maybe_hhdm_response.?;

    hhdm_offset = hhdm_response.offset;
}
