use lazy_static::lazy_static;

use x86_64::structures::gdt::{Descriptor, GlobalDescriptorTable, SegmentSelector};
use x86_64::structures::tss::TaskStateSegment;
use x86_64::VirtAddr;

pub const DOUBLE_FAULT_IST_INDEX: u16 = 0;

lazy_static! {
    static ref TSS: TaskStateSegment = {
        let mut tss = TaskStateSegment::new();

        tss.interrupt_stack_table[DOUBLE_FAULT_IST_INDEX as usize] = {
            const STACK_SIZE: usize = 4096 * 5;
            static mut STACK: [u8; STACK_SIZE] = [0; STACK_SIZE];

            VirtAddr::from_ptr(unsafe { &STACK[STACK_SIZE - 1] })
        };

        tss
    };
}

lazy_static! {
    static ref GDT: (GlobalDescriptorTable, SegmentSelectors) = {
        let mut gdt = GlobalDescriptorTable::new();

        let code_selector = gdt.append(Descriptor::kernel_code_segment());
        let tss_selector = gdt.append(Descriptor::tss_segment(&TSS));

        (
            gdt,
            SegmentSelectors {
                code_selector,
                tss_selector,
            },
        )
    };
}

struct SegmentSelectors {
    code_selector: SegmentSelector,
    tss_selector: SegmentSelector,
}

pub fn init_gdt() {
    use x86_64::instructions::segmentation::{self, Segment};
    use x86_64::instructions::tables;

    GDT.0.load();

    unsafe {
        segmentation::CS::set_reg(GDT.1.code_selector);
        tables::load_tss(GDT.1.tss_selector);
    }
}
