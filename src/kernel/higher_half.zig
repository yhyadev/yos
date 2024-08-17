//! Higher half
//!
//! A utility for our higher half kernel

const limine = @import("limine");

export var hhdm_request: limine.HhdmRequest = .{};

pub var hhdm_offset: usize = undefined;

/// Convert physical addresses to higher half virtual addresses by adding the higher half direct
/// map offset
pub inline fn virtualFromPhysical(physical: u64) u64 {
    return physical + hhdm_offset;
}

pub fn init() void {
    const maybe_hhdm_response = hhdm_request.response;

    if (maybe_hhdm_response == null) {
        @panic("could not retrieve information about the higher half kernel");
    }

    const hhdm_response = maybe_hhdm_response.?;

    hhdm_offset = hhdm_response.offset;
}
