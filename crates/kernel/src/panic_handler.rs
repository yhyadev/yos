use yos_kernel::{halt_loop, println};

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
