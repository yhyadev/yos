pub var scancodes = Stream(u8, 256){ .sink = true };
pub var sink = Stream(u8, 0){ .sink = true };

pub fn Stream(comptime V: type, comptime capacity: usize) type {
    return struct {
        items: [capacity]V = undefined,
        len: usize = 0,

        sink: bool = false,

        const Self = @This();

        pub fn append(self: *Self, value: V) void {
            if (self.sink) return;

            if (self.len + 1 > capacity) @panic("stream exceeded the initial capacity");

            var i: usize = 0;

            var maybe_previous_item: ?V = null;

            while (i < self.len + 1) : (i += 1) {
                if (maybe_previous_item) |previous_item| {
                    maybe_previous_item = self.items[i];
                    self.items[i] = previous_item;
                } else {
                    maybe_previous_item = self.items[i];
                    self.items[i] = value;
                }
            }

            self.len += 1;
        }

        pub fn pop(self: *Self) V {
            self.len -= 1;

            return self.items[self.len];
        }

        pub fn poll(self: *Self) ?V {
            if (self.len == 0) return null;

            return self.pop();
        }
    };
}
