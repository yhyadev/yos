#![no_std]
#![feature(abi_x86_interrupt)]

extern crate alloc;

pub mod allocator;
pub mod apps;
pub mod gdt;
pub mod idt;
pub mod memory;
pub mod task;
pub mod vga;

pub fn halt_loop() -> ! {
    loop {
        x86_64::instructions::hlt();
    }
}
