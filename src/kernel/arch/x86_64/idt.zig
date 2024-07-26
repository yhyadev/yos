const std = @import("std");

const cpu = @import("cpu.zig");
const tty = @import("../../tty.zig");

pub var idt: InterruptDescriptorTable = .{};

pub const InterruptDescriptorTable = extern struct {
    entries: [256]Entry = .{.{}} ** 256,

    comptime {
        std.debug.assert(@sizeOf(InterruptDescriptorTable) == 256 * 16);
    }

    pub const Entry = packed struct(u128) {
        pointer_low: u16 = 0,
        segment_selector: u16 = 0,
        ist: u3 = 1,
        reserved_1: u5 = 0,
        gate_type: u4 = 0b1110,
        reserved_2: u1 = 0,
        dpl: u2 = 0,
        present: u1 = 0,
        pointer_high: u48 = 0,
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

        pub fn setHandler(self: *Entry, pointer: u64) *Entry {
            self.pointer_low = @truncate(pointer);
            self.pointer_high = @truncate(pointer >> 16);

            self.segment_selector = cpu.cs();

            self.present = 1;

            return self;
        }
    };

    pub const Register = packed struct(u80) {
        size: u16,
        pointer: u64,
    };

    pub fn register(self: *InterruptDescriptorTable) Register {
        return Register{
            .size = @sizeOf(InterruptDescriptorTable) - 1,
            .pointer = @intFromPtr(self),
        };
    }

    pub fn load(self: *InterruptDescriptorTable) void {
        cpu.lidt(&self.register());
    }
};

pub const InterruptStackFrame = extern struct {
    instruction_pointer: u64,
    code_segment: u64,
    cpu_flags: u64,
    stack_pointer: u64,
    stack_segment: u64,
};

pub fn init() void {
    idt.entries[0].setHandler(@intFromPtr(&handleDivisionError)).setTrapGate();
    idt.entries[1].setHandler(@intFromPtr(&handleDebug)).setTrapGate();
    idt.entries[3].setHandler(@intFromPtr(&handleBreakpoint)).setTrapGate();
    idt.entries[8].setHandler(@intFromPtr(&handleDoubleFault)).setTrapGate();
    idt.entries[13].setHandler(@intFromPtr(&handleGeneralProtectionFault)).setTrapGate();
    idt.entries[14].setHandler(@intFromPtr(&handlePageFault)).setTrapGate();

    idt.load();
}

fn handleDivisionError(_: *InterruptStackFrame) callconv(.Interrupt) void {
    std.debug.panic("division error\n", .{});
}

fn handleDebug(_: *InterruptStackFrame) callconv(.Interrupt) void {
    tty.print("debug\n", .{});
}

fn handleBreakpoint(_: *InterruptStackFrame) callconv(.Interrupt) void {
    tty.print("breakpoint\n", .{});
}

fn handleDoubleFault(_: *InterruptStackFrame, code: u64) callconv(.Interrupt) void {
    std.debug.panic("double fault: {}\n", .{code});
}

fn handleGeneralProtectionFault(_: *InterruptStackFrame, code: u64) callconv(.Interrupt) void {
    std.debug.panic("general protection fault: {}\n", .{code});
}

fn handlePageFault(_: *InterruptStackFrame, code: u64) callconv(.Interrupt) void {
    std.debug.panic("page fault: {}\n", .{code});
}
