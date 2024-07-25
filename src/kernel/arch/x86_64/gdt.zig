const instructions = @import("instructions.zig");

pub var gdt: GlobalDescriptorTable = .{};

pub const GlobalDescriptorTable = extern struct {
    entries: [3]Entry = .{.{}} ** 3,

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
    }
};

pub fn init() void {
    gdt.entries[1] = GlobalDescriptorTable.Entry.init(0, 0xFFFFF, 0x9A, 0xA);
    gdt.entries[2] = GlobalDescriptorTable.Entry.init(0, 0xFFFFF, 0x92, 0xC);

    gdt.load();
}
