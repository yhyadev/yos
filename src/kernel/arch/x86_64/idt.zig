const std = @import("std");

const cpu = @import("cpu.zig");
const pic = @import("pic.zig");
const stream = @import("../../stream.zig");
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

            self.segment_selector = cpu.segments.cs();

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
        cpu.segments.lidt(&self.register());
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

    idt.entries[pic.timer_interrupt].setHandler(@intFromPtr(&handleTimer)).setInterruptGate();
    idt.entries[pic.keyboard_interrupt].setHandler(@intFromPtr(&handleKeyboard)).setInterruptGate();

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

fn handleOverflow(_: *InterruptStackFrame) callconv(.Interrupt) void {
    tty.print("overflow\n", .{});
}

fn handleBoundRangeExceeded(_: *InterruptStackFrame) callconv(.Interrupt) void {
    std.debug.panic("bound range exceeded\n", .{});
}

fn handleInvalidOpcode(_: *InterruptStackFrame) callconv(.Interrupt) void {
    std.debug.panic("invalid opcode\n", .{});
}

fn handleDeviceNotAvailable(_: *InterruptStackFrame) callconv(.Interrupt) void {
    std.debug.panic("device not available\n", .{});
}

fn handleDoubleFault(_: *InterruptStackFrame, code: u64) callconv(.Interrupt) void {
    std.debug.panic("double fault: {}\n", .{code});
}

fn handleSegmentationFault(_: *InterruptStackFrame, code: u64) callconv(.Interrupt) void {
    std.debug.panic("segmentation fault: {}\n", .{code});
}

fn handleGeneralProtectionFault(_: *InterruptStackFrame, code: u64) callconv(.Interrupt) void {
    std.debug.panic("general protection fault: {}\n", .{code});
}

// This should not panic if we made a page allocator
fn handlePageFault(_: *InterruptStackFrame, code: u64) callconv(.Interrupt) void {
    std.debug.panic("page fault: {}\n", .{code});
}

fn handleX87FloatingPointException(_: *InterruptStackFrame) callconv(.Interrupt) void {
    std.debug.panic("x87 floating point exception\n", .{});
}

fn handleAlignmentCheck(_: *InterruptStackFrame, code: u64) callconv(.Interrupt) void {
    std.debug.panic("alignment check: {}\n", .{code});
}

fn handleMachineCheck(_: *InterruptStackFrame) callconv(.Interrupt) void {
    std.debug.panic("machine check\n", .{});
}

fn handleSIMDFloatingPointException(_: *InterruptStackFrame) callconv(.Interrupt) void {
    std.debug.panic("simd floating point exception\n", .{});
}

fn handleVirtualizationException(_: *InterruptStackFrame) callconv(.Interrupt) void {
    std.debug.panic("virtualization exception\n", .{});
}

fn handleControlProtectionException(_: *InterruptStackFrame, code: u64) callconv(.Interrupt) void {
    std.debug.panic("control protection exception: {}\n", .{code});
}

fn handleHypervisorInjectionException(_: *InterruptStackFrame) callconv(.Interrupt) void {
    std.debug.panic("hypervisor injection exception\n", .{});
}

fn handleVMMCommunicationException(_: *InterruptStackFrame, code: u64) callconv(.Interrupt) void {
    std.debug.panic("vmm communication exception: {}\n", .{code});
}

fn handleSecurityException(_: *InterruptStackFrame, code: u64) callconv(.Interrupt) void {
    std.debug.panic("security exception: {}\n", .{code});
}

fn handleTimer(_: *InterruptStackFrame) callconv(.Interrupt) void {
    pic.notifyEndOfInterrupt(pic.timer_interrupt);
}

fn handleKeyboard(_: *InterruptStackFrame) callconv(.Interrupt) void {
    defer pic.notifyEndOfInterrupt(pic.keyboard_interrupt);

    const scancode = cpu.io.inb(0x60);

    stream.scancodes.append(scancode);
}
