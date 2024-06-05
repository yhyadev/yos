#![no_std]
#![no_main]
#![feature(panic_info_message)]

mod panic_handler;

use ykernel::task::keyboard::ScancodeStream;
use ykernel::task::Task;
use ykernel::{allocator, gdt, idt, memory, task};

use bootloader::{entry_point, BootInfo};

use futures_util::StreamExt;

use x86_64::VirtAddr;

entry_point!(kmain);

pub fn kmain(boot_info: &'static BootInfo) -> ! {
    gdt::init_gdt();
    idt::init_idt();

    unsafe { idt::PICS.lock().initialize() };

    x86_64::instructions::interrupts::enable();

    let physical_memory_offset = VirtAddr::new(boot_info.physical_memory_offset);

    let mut memory_mapper = unsafe { memory::init_mapper(physical_memory_offset) };

    let mut frame_allocator =
        unsafe { memory::init_bootloader_frame_allocator(&boot_info.memory_map) };

    allocator::init_heap(&mut memory_mapper, &mut frame_allocator)
        .expect("heap initialization failed");

    let mut executer = task::executer::Executer::new();

    executer.spawn(Task::new(ignore_keypresses()));

    executer.run();
}

pub async fn ignore_keypresses() {
    let mut scancodes = ScancodeStream::new();
    while let Some(_) = scancodes.next().await {}
}
