#![no_std]
#![no_main]
#![feature(panic_info_message)]

mod panic_handler;

use yos_kernel::task::keyboard::ScancodeStream;
use yos_kernel::{allocator, gdt, interrupts, memory, print, task};

use bootloader::{entry_point, BootInfo};

use futures_util::StreamExt;

use pc_keyboard::{DecodedKey, Keyboard};

use x86_64::VirtAddr;

entry_point!(kmain);

pub fn kmain(boot_info: &'static BootInfo) -> ! {
    gdt::init_gdt();
    interrupts::init_idt();

    unsafe { interrupts::PICS.lock().initialize() };

    x86_64::instructions::interrupts::enable();

    let physical_memory_offset = VirtAddr::new(boot_info.physical_memory_offset);

    let mut memory_mapper = unsafe { memory::init_mapper(physical_memory_offset) };

    let mut frame_allocator =
        unsafe { memory::init_bootloader_frame_allocator(&boot_info.memory_map) };

    allocator::init_heap(&mut memory_mapper, &mut frame_allocator)
        .expect("heap initialization failed");

    let mut executer = task::executer::Executer::new();

    executer.spawn(task::Task::new(print_keypresses()));

    executer.run();
}

pub async fn print_keypresses() {
    let mut scancode_stream = ScancodeStream::new();

    let mut keyboard = Keyboard::new(
        pc_keyboard::ScancodeSet1::new(),
        pc_keyboard::layouts::Us104Key,
        pc_keyboard::HandleControl::Ignore,
    );

    while let Some(scancode) = scancode_stream.next().await {
        if let Ok(Some(key_event)) = keyboard.add_byte(scancode) {
            if let Some(decoded_key) = keyboard.process_keyevent(key_event) {
                match decoded_key {
                    DecodedKey::Unicode(character) => print!("{character}"),
                    DecodedKey::RawKey(_) => (),
                }
            }
        }
    }
}
