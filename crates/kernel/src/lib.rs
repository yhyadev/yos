#![no_std]
#![feature(abi_x86_interrupt)]

pub mod gdt;
pub mod interrupts;
pub mod vga;

pub fn init() {
    gdt::init_gdt();
    interrupts::init_idt();
}

pub fn halt_loop() -> ! {
    println!("halted");

    loop {
        x86_64::instructions::hlt();
    }
}
