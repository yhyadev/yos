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

        pub fn get() RFlags {
            return asm volatile (
                \\pushfq
                \\pop %[result]
                : [result] "={rax}" (-> RFlags),
            );
        }
    };
};

pub const interrupts = struct {
    /// Checks if the interrupts is currently enabled
    pub inline fn enabled() bool {
        return registers.RFlags.get().@"if" == 1;
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
    /// Get the code segment
    pub inline fn cs() u16 {
        return asm volatile ("mov %cs, %[result]"
            : [result] "={rax}" (-> u16),
        );
    }

    /// Load the GDT
    pub inline fn lgdt(gdtr: *const GlobalDescriptorTable.Register) void {
        asm volatile ("lgdt (%[gdtr])"
            :
            : [gdtr] "{rax}" (gdtr),
        );
    }

    /// Reload Segments
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

    /// Load the IDT
    pub inline fn lidt(idtr: *const InterruptDescriptorTable.Register) void {
        asm volatile ("lidt (%[idtr])"
            :
            : [idtr] "{rax}" (idtr),
        );
    }

    /// Load the Task Register (Which is a segment selector of the TSS in the GDT)
    pub inline fn ltr(tr: u16) void {
        asm volatile ("ltr %[tr]"
            :
            : [tr] "{rax}" (tr),
        );
    }
};
