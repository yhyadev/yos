const Stream = @import("stream.zig").Stream;

pub var scancodes = Stream(u8, 256){ .sink = true };
