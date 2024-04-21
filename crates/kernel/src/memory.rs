use bootloader::bootinfo::{MemoryMap, MemoryRegionType};
use x86_64::registers::control::Cr3;
use x86_64::structures::paging::{FrameAllocator, OffsetPageTable, PageTable, PhysFrame, Size4KiB};
use x86_64::{PhysAddr, VirtAddr};

pub unsafe fn active_level_4_table(physical_memory_offset: VirtAddr) -> &'static mut PageTable {
    let (level_4_table_frame, _) = Cr3::read();

    let phys = level_4_table_frame.start_address();
    let virt = physical_memory_offset + phys.as_u64();

    &mut *virt.as_mut_ptr()
}

pub unsafe fn init_mapper(physical_memory_offset: VirtAddr) -> OffsetPageTable<'static> {
    OffsetPageTable::new(
        active_level_4_table(physical_memory_offset),
        physical_memory_offset,
    )
}

pub struct BootloaderFrameAllocator<I> {
    usable_frames: I,
}

unsafe impl<I: Iterator<Item = PhysFrame>> FrameAllocator<Size4KiB>
    for BootloaderFrameAllocator<I>
{
    fn allocate_frame(&mut self) -> Option<PhysFrame<Size4KiB>> {
        self.usable_frames.next()
    }
}

pub unsafe fn init_bootloader_frame_allocator(
    memory_map: &'static MemoryMap,
) -> BootloaderFrameAllocator<impl Iterator<Item = PhysFrame>> {
    let regions = memory_map.iter();

    let usable_regions = regions.filter(|r| r.region_type == MemoryRegionType::Usable);

    let addr_ranges = usable_regions.map(|r| r.range.start_addr()..r.range.end_addr());

    let frame_addreses = addr_ranges.flat_map(|r| r.step_by(4096));

    let usable_frames =
        frame_addreses.map(|addr| PhysFrame::containing_address(PhysAddr::new(addr)));

    BootloaderFrameAllocator { usable_frames }
}
