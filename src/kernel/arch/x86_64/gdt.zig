const instructions = @import("instructions.zig");

pub var backup_kernel_stack: [16 * 4 * 1024]u8 = undefined;

pub var tss: TaskStateSegment.Entry = .{};

pub const TaskStateSegment = struct {
    pub const Entry = packed struct(u832) {
        reserved_1: u32 = 0,
        rsp0: u64 = 0,
        rsp1: u64 = 0,
        rsp2: u64 = 0,
        reserved_2: u64 = 0,
        ist1: u64 = 0,
        ist2: u64 = 0,
        ist3: u64 = 0,
        ist4: u64 = 0,
        ist5: u64 = 0,
        ist6: u64 = 0,
        ist7: u64 = 0,
        reserved_3: u80 = 0,
        iopb: u16 = 0,
    };
};

pub var gdt: GlobalDescriptorTable = .{};

pub const GlobalDescriptorTable = extern struct {
    entries: [5]Entry = .{.{}} ** 5,

    pub const Entry = packed struct(u64) {
        limit_low: u16 = 0,
        base_low: u16 = 0,
        base_middle: u8 = 0,
        access: u8 = 0,
        granularity: u8 = 0,
        base_high: u8 = 0,

        pub fn init(base: u32, limit: u32, access: u8, granularity: u8) Entry {
            return Entry{
                .limit_low = @truncate(limit),
                .base_low = @truncate(base),
                .base_middle = @truncate(base >> 16),
                .base_high = @truncate(base >> 24),
                .granularity = @intCast(((limit >> 16) & 0x0F) | (granularity << 4)),
                .access = access,
            };
        }
    };

    pub fn addKernelCodeSegment(self: *GlobalDescriptorTable) void {
        self.entries[1] = GlobalDescriptorTable.Entry.init(0, 0xFFFFF, 0x9A, 0xA);
    }

    pub fn addKernelDataSegment(self: *GlobalDescriptorTable) void {
        self.entries[2] = GlobalDescriptorTable.Entry.init(0, 0xFFFFF, 0x92, 0xC);
    }

    pub fn addTaskStateSegment(self: *GlobalDescriptorTable) void {
        self.entries[3] = @bitCast(((@sizeOf(TaskStateSegment.Entry) - 1) & 0xffff) | ((@intFromPtr(&tss) & 0xffffff) << 16) | (0b1001 << 40) | (1 << 47) | (((@intFromPtr(&tss) >> 24) & 0xff) << 56));
        self.entries[4] = @bitCast(@intFromPtr(&tss) >> 32);
    }

    pub const Register = packed struct(u80) {
        size: u16,
        pointer: u64,
    };

    pub fn register(self: *GlobalDescriptorTable) Register {
        return Register{
            .size = @sizeOf(GlobalDescriptorTable) - 1,
            .pointer = @intFromPtr(self),
        };
    }

    pub fn load(self: *GlobalDescriptorTable) void {
        instructions.lgdt(&self.register());
        instructions.reloadSegments();
        instructions.ltr(0x18);
    }
};

pub fn init() void {
    tss.ist1 = @intFromPtr(&backup_kernel_stack[backup_kernel_stack.len - 1]);

    gdt.addKernelCodeSegment();
    gdt.addKernelDataSegment();
    gdt.addTaskStateSegment();

    gdt.load();
}
