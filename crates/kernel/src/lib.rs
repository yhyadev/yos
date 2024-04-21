#![no_std]
#![feature(abi_x86_interrupt)]

extern crate alloc;

pub mod allocator;
pub mod gdt;
pub mod interrupts;
pub mod memory;
pub mod vga;

pub fn halt_loop() -> ! {
    loop {
        x86_64::instructions::hlt();
    }
}
