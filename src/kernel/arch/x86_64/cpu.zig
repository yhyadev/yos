//! Central Processing Unit
//!
//! An abstraction over the CPU features

const GlobalDescriptorTable = @import("gdt.zig").GlobalDescriptorTable;

const idt = @import("idt.zig");
const InterruptContext = idt.InterruptContext;
const InterruptDescriptorTable = idt.InterruptDescriptorTable;

const lapic = @import("lapic.zig");

pub const core = struct {
    pub const Info = packed struct {
        kernel_stack: [*]u8 = undefined,
        user_stack: [*]u8 = undefined,
        id: u32 = 0,

        pub inline fn write(value: *Info) void {
            return registers.ModelSpecific.write(.kernel_gs_base, @intFromPtr(value));
        }

        pub inline fn read() *Info {
            return @ptrFromInt(registers.ModelSpecific.read(.kernel_gs_base));
        }
    };
};

pub const paging = struct {
    pub inline fn invlpg(virtual_address: u64) void {
        asm volatile ("invlpg (%[address])"
            :
            : [address] "{rax}" (virtual_address),
            : "memory"
        );
    }
};

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

        /// Write the Flags Register
        pub inline fn write(flags: RFlags) void {
            asm volatile (
                \\push %[result]
                \\popfq
                :
                : [result] "{rax}" (flags),
            );
        }

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
        pub inline fn read(register: Register) u64 {
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

    pub const Cr2 = struct {
        pub inline fn write(value: u64) void {
            asm volatile ("mov %[value], %cr2"
                :
                : [value] "{rax}" (value),
                : "memory"
            );
        }

        pub inline fn read() u64 {
            return asm volatile ("mov %cr2, %[result]"
                : [result] "={rax}" (-> u64),
            );
        }
    };

    pub const Cr3 = struct {
        pub inline fn write(value: u64) void {
            asm volatile ("mov %[value], %cr3"
                :
                : [value] "{rax}" (value),
                : "memory"
            );
        }

        pub inline fn read() u64 {
            return asm volatile ("mov %cr3, %[result]"
                : [result] "={rax}" (-> u64),
            );
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

    /// Offset by the amount of traps in the Interrupt Descriptor Table
    pub inline fn offset(irq: u8) u8 {
        return irq + 32;
    }

    /// Handle specific interrupt request (the interrupt number is offsetted by `offset` function)
    pub fn handle(irq: u8, comptime handler: *const fn (*process.Context) callconv(.C) void) void {
        const lambda = struct {
            pub fn interruptRequestEntry() callconv(.Naked) void {
                // Save the context on stack to be restored later
                asm volatile (
                    \\push %rbp
                    \\push %rax
                    \\push %rbx
                    \\push %rcx
                    \\push %rdx
                    \\push %rdi
                    \\push %rsi
                    \\push %r8
                    \\push %r9
                    \\push %r10
                    \\push %r11
                    \\push %r12
                    \\push %r13
                    \\push %r14
                    \\push %r15
                    \\mov %ds, %rax
                    \\push %rax
                    \\mov %es, %rax
                    \\push %rax
                    \\mov $0x10, %ax
                    \\mov %ax, %ds
                    \\mov %ax, %es
                    \\cld
                );

                // Allow the handler to modify the context by passing a pointer to it
                asm volatile (
                    \\mov %rsp, %rdi
                );

                // Now call the handler using the function pointer we have, this is possible with
                // the derefrence operator in AT&T assembly syntax
                asm volatile (
                    \\call *%[handler]
                    :
                    : [handler] "{rax}" (handler),
                );

                // Restore the context (which is potentially modified)
                asm volatile (
                    \\pop %rax
                    \\mov %rax, %es
                    \\pop %rax
                    \\mov %rax, %ds
                    \\pop %r15
                    \\pop %r14
                    \\pop %r13
                    \\pop %r12
                    \\pop %r11
                    \\pop %r10
                    \\pop %r9
                    \\pop %r8
                    \\pop %rsi
                    \\pop %rdi
                    \\pop %rdx
                    \\pop %rcx
                    \\pop %rbx
                    \\pop %rax
                    \\pop %rbp
                );

                // Return to the code we interrupted
                asm volatile (
                    \\iretq
                );
            }
        };

        // I am shameful to use idt.idt but there is no other way
        idt.idt.entries[offset(irq)].setHandler(@intFromPtr(&lambda.interruptRequestEntry)).setInterruptGate();
    }

    /// Must be called at the end of an interrupt request
    pub inline fn end() void {
        lapic.getLapic().write(.eoi, 0);
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

pub const process = struct {
    /// Context of the current process
    pub const Context = extern struct {
        es: u64 = 0,
        ds: u64 = 0,
        r15: u64 = 0,
        r14: u64 = 0,
        r13: u64 = 0,
        r12: u64 = 0,
        r11: u64 = 0,
        r10: u64 = 0,
        r9: u64 = 0,
        r8: u64 = 0,
        rsi: u64 = 0,
        rdi: u64 = 0,
        rdx: u64 = 0,
        rcx: u64 = 0,
        rbx: u64 = 0,
        rax: u64 = 0,
        rbp: u64 = 0,
        rip: u64 = 0,
        cs: u64 = 0,
        rflags: u64 = 0,
        rsp: u64 = 0,
        ss: u64 = 0,
    };

    /// Wait endlessly
    pub inline fn hang() noreturn {
        while (true) {
            interrupts.hlt();
        }
    }
};
