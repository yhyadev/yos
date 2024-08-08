const std = @import("std");

const cpu = @import("cpu.zig");
const gdt = @import("gdt.zig");

pub fn init() void {
    cpu.registers.ModelSpecific.write(.star, (0x8 << 32) | ((0x18 - 0x8) << 48));
    cpu.registers.ModelSpecific.write(.lstar, @intFromPtr(&syscallEntry));
    cpu.registers.ModelSpecific.write(.efer, cpu.registers.ModelSpecific.read(.efer) | 1);
    cpu.registers.ModelSpecific.write(.sf_mask, 0b1111110111111111010101);

    cpu.core.Info.read().kernel_stack = &gdt.backup_kernel_stack;
}

fn syscallEntry() callconv(.Naked) void {
    cpu.interrupts.disable();

    // Swap to kernel gs base
    asm volatile ("swapgs");

    // Save the user stack and Restore the kernel stack
    asm volatile (
        \\movq %rsp, %gs:8
        \\movq %gs:0, %rsp
    );

    // Save the context on stack to be restored later
    asm volatile (
        \\push $0x18
        \\pushq %gs:8
        \\push %r11
        \\push $0x20
        \\push %rcx
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

    // Swap again to user gs base
    asm volatile ("swapgs");

    asm volatile ("xor %rbp, %rbp");

    // Now call the handler using the function pointer we have, this is possible with
    // the derefrence operator in AT&T assembly syntax
    asm volatile (
        \\call *%[handler]
        :
        : [handler] "{rax}" (&syscallHandler),
    );

    // Swap to kernel gs base
    asm volatile ("swapgs");

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

    // Return back to user stack
    asm volatile (
        \\movq %gs:8, %rsp
    );

    // Swap again to user gs base
    asm volatile ("swapgs");

    cpu.interrupts.enable();

    asm volatile (
        \\sysretq
    );
}

fn syscallHandler(context: *cpu.process.Context) callconv(.C) void {
    const syscall_functions = @import("../../syscall.zig");
    const syscall_function_types = @typeInfo(syscall_functions);

    switch (context.rax) {
        inline 0...syscall_function_types.Struct.decls.len - 1 => |code| {
            const syscall_function = @field(syscall_functions, syscall_function_types.Struct.decls[code].name);
            const syscall_function_type = @typeInfo(@TypeOf(syscall_function));

            comptime std.debug.assert(syscall_function_type.Fn.params.len <= 6);

            switch (syscall_function_type.Fn.params.len - 1) {
                0 => syscall_function(context),
                1 => syscall_function(context, context.rdi),
                2 => syscall_function(context, context.rdi, context.rsi),
                3 => syscall_function(context, context.rdi, context.rsi, context.rdx),
                4 => syscall_function(context, context.rdi, context.rsi, context.rdx, context.r10),
                5 => syscall_function(context, context.rdi, context.rsi, context.rdx, context.r10, context.r8),
                6 => syscall_function(context, context.rdi, context.rsi, context.rdx, context.r10, context.r8, context.r9),

                else => unreachable,
            }
        },

        else => {},
    }
}
