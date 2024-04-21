#![no_std]
#![no_main]
#![feature(panic_info_message)]

use yos_kernel::{halt_loop, init, print, println};

use core::panic::PanicInfo;

#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    if let Some(message) = info.message() {
        println!("panic occured: {}", message);
    } else {
        println!("panic occured with no message");
    }

    halt_loop();
}

#[no_mangle]
pub extern "C" fn _start() -> ! {
    print!("initializing the kernel.. ");
    init();
    println!("ok");

    halt_loop();
}
