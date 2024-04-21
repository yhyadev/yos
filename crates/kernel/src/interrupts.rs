use crate::println;

use lazy_static::lazy_static;

use x86_64::structures::idt::{InterruptDescriptorTable, InterruptStackFrame};

lazy_static! {
    static ref IDT: InterruptDescriptorTable = {
        let mut idt = InterruptDescriptorTable::new();

        idt.breakpoint.set_handler_fn(breakpoint_handler);
        idt.double_fault.set_handler_fn(double_fault_handler);

        idt
    };
}

pub fn init_idt() {
    IDT.load();
}

extern "x86-interrupt" fn breakpoint_handler(_: InterruptStackFrame) {
    println!("breakpoint");
}

extern "x86-interrupt" fn double_fault_handler(_: InterruptStackFrame, error_code: u64) -> ! {
    panic!("double fault, error code ({})", error_code);
}
