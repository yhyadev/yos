use linked_list_allocator::LockedHeap;

use x86_64::structures::paging::mapper::MapToError;
use x86_64::structures::paging::page::PageRangeInclusive;
use x86_64::structures::paging::{FrameAllocator, Mapper, Page, PageTableFlags, Size4KiB};
use x86_64::VirtAddr;

#[global_allocator]
static ALLOCATOR: LockedHeap = LockedHeap::empty();

pub const HEAP_SIZE: usize = 100 * 1024;
pub const HEAP_START: usize = 0x4444_4444_0000;

pub fn init_heap(
    memory_mapper: &mut impl Mapper<Size4KiB>,
    frame_allocator: &mut impl FrameAllocator<Size4KiB>,
) -> Result<(), MapToError<Size4KiB>> {
    let heap_start_address = VirtAddr::new(HEAP_START as u64);

    let page_range: PageRangeInclusive<Size4KiB> = {
        let heap_end_address = heap_start_address + HEAP_SIZE as u64 - 1;
        let heap_start_page = Page::containing_address(heap_start_address);
        let heap_end_page = Page::containing_address(heap_end_address);

        Page::range_inclusive(heap_start_page, heap_end_page)
    };

    for page in page_range {
        let frame = frame_allocator
            .allocate_frame()
            .ok_or(MapToError::FrameAllocationFailed)?;

        let flags = PageTableFlags::PRESENT | PageTableFlags::WRITABLE;

        unsafe {
            memory_mapper
                .map_to(page, frame, flags, frame_allocator)?
                .flush();
        }
    }

    unsafe {
        ALLOCATOR
            .lock()
            .init(heap_start_address.as_mut_ptr(), HEAP_SIZE);
    }

    Ok(())
}
