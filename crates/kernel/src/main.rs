#![no_std]
#![no_main]
#![feature(panic_info_message)]

mod panic_handler;

use yos_kernel::{allocator, gdt, halt_loop, interrupts, memory};

use x86_64::VirtAddr;

use bootloader::{entry_point, BootInfo};

entry_point!(kmain);

pub fn kmain(boot_info: &'static BootInfo) -> ! {
    gdt::init_gdt();
    interrupts::init_idt();

    let physical_memory_offset = VirtAddr::new(boot_info.physical_memory_offset);

    let mut memory_mapper = unsafe { memory::init_mapper(physical_memory_offset) };

    let mut frame_allocator =
        unsafe { memory::init_bootloader_frame_allocator(&boot_info.memory_map) };

    allocator::init_heap(&mut memory_mapper, &mut frame_allocator)
        .expect("heap initialization failed");

    halt_loop();
}
