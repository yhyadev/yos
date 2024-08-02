const std = @import("std");
const acpi = @import("../../acpi.zig");

var base_address: usize = 0xFEC00000;

const Register = enum {
    ioapicid,
    ioapicver,
    ioapicarb,

    fn getOffset(self: Register) u8 {
        return switch (self) {
            .ioapicid => 0x00,
            .ioapicver => 0x01,
            .ioapicarb => 0x02,
        };
    }

    fn Type(self: Register) type {
        return switch (self) {
            .ioapicid => u32,
            .ioapicver => u32,
            .ioapicarb => u32,
        };
    }
};

fn read(comptime register: Register) register.Type() {
    @as(*allowzero u8, @ptrFromInt(base_address)).* = register.getOffset();
    return @as(*allowzero register.Type(), @ptrFromInt(base_address + 0x10)).*;
}

fn write(comptime register: Register, value: register.Type()) void {
    @as(*allowzero u8, @ptrFromInt(base_address)).* = register.getOffset();
    @as(*allowzero register.Type(), @ptrFromInt(base_address + 0x10)).* = value;
}

pub const RedEntry = packed struct(u64) {
    vector: u8,
    delivery_mode: DeliveryMode,
    destination_mode: DestinationMode,
    delivery_status: u1,
    polarity: Polarity,
    remote_irr: u1,
    trigger_mode: TriggerMode,
    mask: bool,
    reserved: u39 = 0,
    destination: u8,

    pub const DeliveryMode = enum(u3) {
        fixed = 0b000,
        lowest = 0b001,
        smi = 0b010,
        nmi = 0b100,
        init = 0b101,
        ext_int = 0b111,
    };

    pub const DestinationMode = enum(u1) {
        physical = 0,
        logical = 1,
    };

    pub const Polarity = enum(u1) {
        active_high = 0,
        active_low = 1,
    };

    pub const TriggerMode = enum(u1) {
        edge = 0,
        level = 1,
    };
};

pub fn readRedEntry(n: usize) RedEntry {
    const offset: u8 = @truncate(0x10 + n * 2);

    @as(*allowzero u8, @ptrFromInt(base_address)).* = offset;
    const low = @as(*allowzero u32, @ptrFromInt(base_address + 0x10)).*;

    @as(*allowzero u8, @ptrFromInt(base_address)).* = offset + 1;
    const high = @as(*allowzero u32, @ptrFromInt(base_address + 0x10)).*;

    const int: u64 = (@as(u64, high) << 32) | low;

    return @bitCast(int);
}

pub fn writeRedEntry(n: usize, entry: RedEntry) void {
    const offset: u8 = @truncate(0x10 + n * 2);

    const int: u64 = @bitCast(entry);

    @as(*allowzero u8, @ptrFromInt(base_address)).* = offset;
    @as(*allowzero u32, @ptrFromInt(base_address + 0x10)).* = @truncate(int);

    @as(*allowzero u8, @ptrFromInt(base_address)).* = offset + 1;
    @as(*allowzero u32, @ptrFromInt(base_address + 0x10)).* = @truncate(int >> 32);
}

pub fn init() void {
    if (acpi.madt) |madt| {
        base_address = madt.getIoApicAddr();
    } else {
        @panic("no io apic available");
    }
}
