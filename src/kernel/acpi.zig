const std = @import("std");
const limine = @import("limine");

const memory = @import("memory.zig");

export var rsdp_request: limine.RsdpRequest = .{};

pub var rsdt: *Rsdt = undefined;
pub var fadt: ?*Fadt = null;
pub var dsdt: ?*Dsdt = null;
pub var madt: ?*Madt = null;

/// Root System Description Pointer
pub const Rsdp = extern struct {
    signature: [8]u8 align(1),
    checksum: u8 align(1),
    oemid: [6]u8 align(1),
    revision: u8 align(1),
    rsdt_address: u32 align(1),
};

/// System Description Table Header
pub const SdtHeader = extern struct {
    signature: [4]u8 align(1),
    length: u32 align(1),
    revision: u8 align(1),
    checksum: u8 align(1),
    oemid: [6]u8 align(1),
    oem_table_id: [8]u8 align(1),
    oem_revision: u32 align(1),
    creator_id: u32 align(1),
    creator_revision: u32 align(1),
};

/// Root System Description Table
pub const Rsdt = extern struct {
    header: SdtHeader align(1),
    entries: [256]u32 align(1),
};

/// Fixed ACPI Description Table
pub const Fadt = extern struct {
    header: SdtHeader align(1),
    firmware_ctrl: u32 align(1),
    dsdt: u32 align(1),
    reserved_1: u32 align(1) = 0,
    preferred_power_management_profile: u8 align(1),
    sci_interrupt: u16 align(1),
    smi_command_port: u32 align(1),
    acpi_enable: u8 align(1),
    acpi_disable: u8 align(1),
    s4bios_req: u8 align(1),
    pstate_control: u8 align(1),
    pm1a_event_block: u32 align(1),
    pm1b_event_block: u32 align(1),
    pm1a_control_block: u32 align(1),
    pm1b_control_block: u32 align(1),
    pm2_control_block: u32 align(1),
    pm_timer_block: u32 align(1),
    gpe0_block: u32 align(1),
    gpe1_block: u32 align(1),
    pm1_event_length: u8 align(1),
    pm1_control_length: u8 align(1),
    pm2_control_length: u8 align(1),
    pm_timer_length: u8 align(1),
    gpe0_length: u8 align(1),
    gpe1_length: u8 align(1),
    gpe1_base: u8 align(1),
    cstate_control: u8 align(1),
    worst_c2_latency: u16 align(1),
    worst_c3_latency: u16 align(1),
    flush_size: u16 align(1),
    flush_stride: u16 align(1),
    duty_offset: u8 align(1),
    duty_width: u8 align(1),
    day_alarm: u8 align(1),
    month_alarm: u8 align(1),
    century: u8 align(1),
    reserved_2: u16 align(1) = 0,
    reserved_3: u8 align(1) = 0,
    flags: u32 align(1),
    reset_reg: [12]u8 align(1),
    reset_value: u8 align(1),
    reserved_4: u16 align(1) = 0,
    reserved_5: u8 align(1) = 0,
};

/// Differentiated Description Table
pub const Dsdt = extern struct {
    header: SdtHeader align(1),
};

/// Multiple APIC Description Table
pub const Madt = extern struct {
    header: SdtHeader align(1),
    lapic_addr: u32 align(1),
    flags: u32 align(1),

    pub fn getIoApicAddr(self: *Madt) usize {
        var ptr = @as([*]u8, @ptrCast(self));

        ptr += @sizeOf(Madt);

        while (true) {
            if (ptr[0] == 1) {
                return memory.virtFromPhys(std.mem.readInt(u32, ptr[4..8], .little));
            } else {
                ptr += ptr[1];
            }
        }
    }
};

pub fn init() void {
    if (rsdp_request.response == null) {
        @panic("could not retrieve information about the rsdp");
    }

    const rsdp_response = rsdp_request.response.?;

    const rsdp: *Rsdp = @ptrCast(@alignCast(rsdp_response.address));

    if (!std.mem.eql(u8, "RSD PTR ", &rsdp.signature)) {
        @panic("bad rsdp signature");
    }

    switch (rsdp.revision) {
        0 => {
            var rsdp_checksum: usize = 0;

            for (std.mem.asBytes(rsdp)) |byte| rsdp_checksum += byte;

            if ((rsdp_checksum & 0xFF) != 0) {
                @panic("bad rsdp signature");
            }

            rsdt = @ptrFromInt(memory.virtFromPhys(rsdp.rsdt_address));

            if (!std.mem.eql(u8, "RSDT", &rsdt.header.signature)) {
                @panic("bad rsdt signature");
            }

            const rsdt_entry_count = (rsdt.header.length - @sizeOf(SdtHeader)) / 4;

            for (0..rsdt_entry_count) |i| {
                const rsdt_entry: *anyopaque = @ptrFromInt(memory.virtFromPhys(rsdt.entries[i]));

                if (std.mem.eql(u8, "FACP", &@as(*SdtHeader, @ptrCast(rsdt_entry)).signature)) {
                    fadt = @ptrCast(rsdt_entry);

                    dsdt = @ptrFromInt(memory.virtFromPhys(fadt.?.dsdt));

                    if (!std.mem.eql(u8, "DSDT", &dsdt.?.header.signature)) {
                        @panic("bad dsdt signature");
                    }
                } else if (std.mem.eql(u8, "APIC", &@as(*SdtHeader, @ptrCast(rsdt_entry)).signature)) {
                    madt = @ptrCast(rsdt_entry);
                }
            }
        },

        else => @panic("unsupported acpi version"),
    }
}
