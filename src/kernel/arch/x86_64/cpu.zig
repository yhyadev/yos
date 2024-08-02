const GlobalDescriptorTable = @import("gdt.zig").GlobalDescriptorTable;
const InterruptDescriptorTable = @import("idt.zig").InterruptDescriptorTable;

pub const registers = struct {
    pub const RFlags = packed struct(u64) {
        cf: u1,
        reserved_1: u1,
        pf: u1,
        reserved_2: u1,
        af: u1,
        reserved_3: u1,
        zf: u1,
        sf: u1,
        tf: u1,
        @"if": u1,
        df: u1,
        of: u1,
        iopl: u2,
        nt: u1,
        reserved_4: u1,
        rf: u1,
        vm: u1,
        ac: u1,
        vif: u1,
        vip: u1,
        id: u1,
        reserved_5: u42,

        /// Read the Flags Register
        pub inline fn read() RFlags {
            return asm volatile (
                \\pushfq
                \\pop %[result]
                : [result] "={rax}" (-> RFlags),
            );
        }
    };

    pub const ModelSpecific = struct {
        pub const Register = enum(u32) {
            apic_base = 0x0000_001B,
            efer = 0xC000_0080,
            star = 0xC000_0081,
            lstar = 0xC000_0082,
            cstar = 0xC000_0083,
            sf_mask = 0xC000_0084,
            gs_base = 0xC000_0101,
            kernel_gs_base = 0xC000_0102,
        };

        /// Write to a Model Specific Register
        pub inline fn write(register: Register, value: usize) void {
            const value_low: u32 = @truncate(value);
            const value_high: u32 = @truncate(value >> 32);

            asm volatile ("wrmsr"
                :
                : [register] "{ecx}" (@intFromEnum(register)),
                  [value_low] "{eax}" (value_low),
                  [value_high] "{edx}" (value_high),
            );
        }

        /// Read a Model Specific Register
        pub inline fn read(register: Register) usize {
            var value_low: u32 = undefined;
            var value_high: u32 = undefined;

            asm volatile ("rdmsr"
                : [value_low] "={eax}" (value_low),
                  [value_high] "={edx}" (value_high),
                : [register] "{ecx}" (@intFromEnum(register)),
            );

            return (@as(usize, value_high) << 32) | value_low;
        }
    };
};

pub const interrupts = struct {
    /// Checks if the interrupts is currently enabled
    pub inline fn enabled() bool {
        return registers.RFlags.read().@"if" == 1;
    }

    /// Enable interrupts
    pub inline fn enable() void {
        asm volatile ("sti");
    }

    /// Disable interrupts
    pub inline fn disable() void {
        asm volatile ("cli");
    }

    /// Invoke interrupt
    pub inline fn int(irq: u8) void {
        asm volatile ("int %[irq]"
            :
            : [irq] "N" (irq),
        );
    }

    /// Wait for interrupt, this is usually used to put the CPU to sleep
    pub inline fn hlt() void {
        asm volatile ("hlt");
    }
};

pub const io = struct {
    /// Get a byte from an io port
    pub inline fn inb(port: u16) u8 {
        return asm volatile ("inb %[port], %[result]"
            : [result] "={al}" (-> u8),
            : [port] "N{dx}" (port),
        );
    }

    /// Send a byte to io port
    pub inline fn outb(port: u16, byte: u8) void {
        asm volatile ("outb %[byte], %[port]"
            :
            : [byte] "{al}" (byte),
              [port] "N{dx}" (port),
        );
    }
};

pub const segments = struct {
    /// Get the Code Segment Selector
    pub inline fn cs() u16 {
        return asm volatile ("mov %cs, %[result]"
            : [result] "={rax}" (-> u16),
        );
    }

    /// Load the Global Descriptor Table
    pub inline fn lgdt(gdtr: *const GlobalDescriptorTable.Register) void {
        asm volatile ("lgdt (%[gdtr])"
            :
            : [gdtr] "{rax}" (gdtr),
        );
    }

    pub noinline fn reloadSegments() void {
        asm volatile (
            \\pushq $0x08
            \\pushq $reloadCodeSegment
            \\lretq
            \\
            \\reloadCodeSegment:
            \\  mov $0x10, %ax
            \\  mov %ax, %es
            \\  mov %ax, %ss
            \\  mov %ax, %ds
            \\  mov %ax, %fs
            \\  mov %ax, %gs
        );
    }

    /// Load the Interrupt Descriptor Table
    pub inline fn lidt(idtr: *const InterruptDescriptorTable.Register) void {
        asm volatile ("lidt (%[idtr])"
            :
            : [idtr] "{rax}" (idtr),
        );
    }

    /// Load the Task Register (Which is a Task State Segment Selector in the Global Descriptor Table)
    pub inline fn ltr(tr: u16) void {
        asm volatile ("ltr %[tr]"
            :
            : [tr] "{rax}" (tr),
        );
    }
};
