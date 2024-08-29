//! Stream
//!
//! An implementation of first in first out stream

const abi = @import("abi");

const SpinLock = @import("locks/SpinLock.zig");

pub var key_events = Stream(abi.KeyEvent, 256){};

pub fn Stream(comptime V: type, comptime capacity: usize) type {
    return struct {
        items: [capacity]V = undefined,
        len: usize = 0,
        mutex: SpinLock = .{},

        const Self = @This();

        pub fn append(self: *Self, value: V) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.len + 1 > capacity) {
                self.len = 0;
            }

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
            self.mutex.lock();
            defer self.mutex.unlock();

            self.len -= 1;

            return self.items[self.len];
        }

        pub fn poll(self: *Self) ?V {
            if (self.len == 0) return null;

            return self.pop();
        }
    };
}
