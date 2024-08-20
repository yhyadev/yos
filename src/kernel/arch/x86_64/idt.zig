//! Interrupt Descriptor Table
//!
//! A fancy thing made by Intel, cam be also called interrupt vector table

const std = @import("std");

const cpu = @import("cpu.zig");
const console = @import("../../console.zig");

pub var idt: InterruptDescriptorTable = .{};

pub const InterruptDescriptorTable = extern struct {
    entries: [256]Entry = .{.{}} ** 256,

    comptime {
        std.debug.assert(@sizeOf(InterruptDescriptorTable) == 256 * 16);
    }

    pub const Entry = packed struct(u128) {
        address_low: u16 = 0,
        segment_selector: u16 = 0,
        ist: u3 = 1,
        reserved_1: u5 = 0,
        gate_type: u4 = 0b1110,
        reserved_2: u1 = 0,
        dpl: u2 = 0,
        present: u1 = 0,
        address_high: u48 = 0,
        reserved_3: u32 = 0,

        comptime {
            std.debug.assert(@sizeOf(Entry) == 16);
        }

        pub fn setInterruptGate(self: *Entry) void {
            self.gate_type = 0b1110;
        }

        pub fn setTrapGate(self: *Entry) void {
            self.gate_type = 0b1111;
        }

        pub fn setHandler(self: *Entry, address: u64) *Entry {
            self.address_low = @truncate(address);
            self.address_high = @truncate(address >> 16);

            self.segment_selector = cpu.segments.cs();

            self.present = 1;

            return self;
        }
    };

    pub const Register = packed struct(u80) {
        size: u16,
        address: u64,
    };

    pub fn register(self: *InterruptDescriptorTable) Register {
        return Register{
            .size = @sizeOf(InterruptDescriptorTable) - 1,
            .address = @intFromPtr(self),
        };
    }

    pub fn load(self: *InterruptDescriptorTable) void {
        cpu.segments.lidt(&self.register());
    }
};

pub const InterruptContext = extern struct {
    rip: u64,
    cs: u64,
    rflags: u64,
    rsp: u64,
    ss: u64,
};

pub fn init() void {
    idt.entries[0].setHandler(@intFromPtr(&handleDivisionError)).setTrapGate();
    idt.entries[1].setHandler(@intFromPtr(&handleDebug)).setTrapGate();
    idt.entries[3].setHandler(@intFromPtr(&handleBreakpoint)).setTrapGate();
    idt.entries[4].setHandler(@intFromPtr(&handleOverflow)).setTrapGate();
    idt.entries[5].setHandler(@intFromPtr(&handleBoundRangeExceeded)).setTrapGate();
    idt.entries[6].setHandler(@intFromPtr(&handleInvalidOpcode)).setTrapGate();
    idt.entries[7].setHandler(@intFromPtr(&handleDeviceNotAvailable)).setTrapGate();
    idt.entries[8].setHandler(@intFromPtr(&handleDoubleFault)).setTrapGate();
    idt.entries[10].setHandler(@intFromPtr(&handleSegmentationFault)).setTrapGate();
    idt.entries[11].setHandler(@intFromPtr(&handleSegmentationFault)).setTrapGate();
    idt.entries[12].setHandler(@intFromPtr(&handleSegmentationFault)).setTrapGate();
    idt.entries[13].setHandler(@intFromPtr(&handleGeneralProtectionFault)).setTrapGate();
    idt.entries[14].setHandler(@intFromPtr(&handlePageFault)).setTrapGate();
    idt.entries[16].setHandler(@intFromPtr(&handleX87FloatingPointException)).setTrapGate();
    idt.entries[17].setHandler(@intFromPtr(&handleAlignmentCheck)).setTrapGate();
    idt.entries[18].setHandler(@intFromPtr(&handleMachineCheck)).setTrapGate();
    idt.entries[19].setHandler(@intFromPtr(&handleSIMDFloatingPointException)).setTrapGate();
    idt.entries[20].setHandler(@intFromPtr(&handleVirtualizationException)).setTrapGate();
    idt.entries[21].setHandler(@intFromPtr(&handleControlProtectionException)).setTrapGate();
    idt.entries[28].setHandler(@intFromPtr(&handleHypervisorInjectionException)).setTrapGate();
    idt.entries[29].setHandler(@intFromPtr(&handleVMMCommunicationException)).setTrapGate();
    idt.entries[30].setHandler(@intFromPtr(&handleSecurityException)).setTrapGate();

    idt.load();
}

fn handleDivisionError(_: *InterruptContext) callconv(.Interrupt) void {
    std.debug.panic("division error\n", .{});
}

fn handleDebug(_: *InterruptContext) callconv(.Interrupt) void {
    console.print("debug\n", .{});
}

fn handleBreakpoint(_: *InterruptContext) callconv(.Interrupt) void {
    console.print("breakpoint\n", .{});
}

fn handleOverflow(_: *InterruptContext) callconv(.Interrupt) void {
    console.print("overflow\n", .{});
}

fn handleBoundRangeExceeded(_: *InterruptContext) callconv(.Interrupt) void {
    std.debug.panic("bound range exceeded\n", .{});
}

fn handleInvalidOpcode(_: *InterruptContext) callconv(.Interrupt) void {
    std.debug.panic("invalid opcode\n", .{});
}

fn handleDeviceNotAvailable(_: *InterruptContext) callconv(.Interrupt) void {
    std.debug.panic("device not available\n", .{});
}

fn handleDoubleFault(_: *InterruptContext, code: u64) callconv(.Interrupt) void {
    std.debug.panic("double fault: {}\n", .{code});
}

fn handleSegmentationFault(_: *InterruptContext, code: u64) callconv(.Interrupt) void {
    std.debug.panic("segmentation fault: {}\n", .{code});
}

fn handleGeneralProtectionFault(_: *InterruptContext, code: u64) callconv(.Interrupt) void {
    std.debug.panic("general protection fault: {}\n", .{code});
}

fn handlePageFault(s: *InterruptContext, code: u64) callconv(.Interrupt) void {
    std.debug.panic("page fault: {} 0x{x} 0x{x}\n", .{ code, cpu.registers.Cr2.read(), s.rip });
}

fn handleX87FloatingPointException(_: *InterruptContext) callconv(.Interrupt) void {
    std.debug.panic("x87 floating point exception\n", .{});
}

fn handleAlignmentCheck(_: *InterruptContext, code: u64) callconv(.Interrupt) void {
    std.debug.panic("alignment check: {}\n", .{code});
}

fn handleMachineCheck(_: *InterruptContext) callconv(.Interrupt) void {
    std.debug.panic("machine check\n", .{});
}

fn handleSIMDFloatingPointException(_: *InterruptContext) callconv(.Interrupt) void {
    std.debug.panic("simd floating point exception\n", .{});
}

fn handleVirtualizationException(_: *InterruptContext) callconv(.Interrupt) void {
    std.debug.panic("virtualization exception\n", .{});
}

fn handleControlProtectionException(_: *InterruptContext, code: u64) callconv(.Interrupt) void {
    std.debug.panic("control protection exception: {}\n", .{code});
}

fn handleHypervisorInjectionException(_: *InterruptContext) callconv(.Interrupt) void {
    std.debug.panic("hypervisor injection exception\n", .{});
}

fn handleVMMCommunicationException(_: *InterruptContext, code: u64) callconv(.Interrupt) void {
    std.debug.panic("vmm communication exception: {}\n", .{code});
}

fn handleSecurityException(_: *InterruptContext, code: u64) callconv(.Interrupt) void {
    std.debug.panic("security exception: {}\n", .{code});
}
