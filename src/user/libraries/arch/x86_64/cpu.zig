const abi = @import("abi");

pub const syscall = struct {
    pub fn syscall0(code: abi.Syscode) usize {
        return asm volatile ("syscall"
            : [result] "={rax}" (-> usize),
            : [code] "{rax}" (@intFromEnum(code)),
            : "rcx", "r11", "memory"
        );
    }

    pub fn syscall1(code: abi.Syscode, arg1: usize) usize {
        return asm volatile ("syscall"
            : [result] "={rax}" (-> usize),
            : [code] "{rax}" (@intFromEnum(code)),
              [arg1] "{rdi}" (arg1),
            : "rcx", "r11", "memory"
        );
    }

    pub fn syscall2(code: abi.Syscode, arg1: usize, arg2: usize) usize {
        return asm volatile ("syscall"
            : [result] "={rax}" (-> usize),
            : [code] "{rax}" (@intFromEnum(code)),
              [arg1] "{rdi}" (arg1),
              [arg2] "{rsi}" (arg2),
            : "rcx", "r11", "memory"
        );
    }

    pub fn syscall3(code: abi.Syscode, arg1: usize, arg2: usize, arg3: usize) usize {
        return asm volatile ("syscall"
            : [result] "={rax}" (-> usize),
            : [code] "{rax}" (@intFromEnum(code)),
              [arg1] "{rdi}" (arg1),
              [arg2] "{rsi}" (arg2),
              [arg3] "{rdx}" (arg3),
            : "rcx", "r11", "memory"
        );
    }

    pub fn syscall4(code: abi.Syscode, arg1: usize, arg2: usize, arg3: usize, arg4: usize) usize {
        return asm volatile ("syscall"
            : [result] "={rax}" (-> usize),
            : [code] "{rax}" (@intFromEnum(code)),
              [arg1] "{rdi}" (arg1),
              [arg2] "{rsi}" (arg2),
              [arg3] "{rdx}" (arg3),
              [arg4] "{r10}" (arg4),
            : "rcx", "r11", "memory"
        );
    }

    pub fn syscall5(code: abi.Syscode, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize) usize {
        return asm volatile ("syscall"
            : [result] "={rax}" (-> usize),
            : [code] "{rax}" (@intFromEnum(code)),
              [arg1] "{rdi}" (arg1),
              [arg2] "{rsi}" (arg2),
              [arg3] "{rdx}" (arg3),
              [arg4] "{r10}" (arg4),
              [arg5] "{r8}" (arg5),
            : "rcx", "r11", "memory"
        );
    }

    pub fn syscall6(
        code: abi.Syscode,
        arg1: usize,
        arg2: usize,
        arg3: usize,
        arg4: usize,
        arg5: usize,
        arg6: usize,
    ) usize {
        return asm volatile ("syscall"
            : [result] "={rax}" (-> usize),
            : [code] "{rax}" (@intFromEnum(code)),
              [arg1] "{rdi}" (arg1),
              [arg2] "{rsi}" (arg2),
              [arg3] "{rdx}" (arg3),
              [arg4] "{r10}" (arg4),
              [arg5] "{r8}" (arg5),
              [arg6] "{r9}" (arg6),
            : "rcx", "r11", "memory"
        );
    }
};
