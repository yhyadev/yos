.section ".text.boot"
.global _start
.org 0x80000
_start:
initialize_stack:
    adr x5, _start
    mov sp, x5

load_bss_info:
    adr x5, __bss_start
    ldr x6, __bss_size

    cbz x6, run_kernel

initialize_bss:
    str xzr, [x5], #0 
    sub x6, x6, #1

    cbnz x6, initialize_bss

run_kernel:
    bl kmain

// For failsafe only! The kernel should not return
halt:
    wfe
    b halt
