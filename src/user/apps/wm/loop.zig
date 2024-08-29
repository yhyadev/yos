//! Loop
//!
//! The event loop that runs all the time, contains key mapping to actions and other functionalities

const std = @import("std");
const abi = @import("abi");
const core = @import("core");

const display = @import("display.zig");

var backing_allocator: std.mem.Allocator = undefined;

var windows: std.AutoHashMapUnmanaged(usize, Window) = .{};
var windows_ordering: std.ArrayListUnmanaged(*Window) = .{};

const Window = struct {
    buffer: []abi.Color = undefined,
    x: usize = 0,
    y: usize = 0,
    width: usize = 0,
    height: usize = 0,

    fn draw(self: Window) void {
        display.drawCustomRectangle(self.x, self.y, self.width, self.height, self.buffer);
    }
};

fn drawWindows() void {
    for (windows_ordering.items) |window| {
        window.draw();
    }
}

fn handleEvents() void {
    handleKeyEvents() catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
    };

    handleMessageEvents() catch |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
    };
}

const key_handler = struct {
    var keys_pressed: std.AutoHashMapUnmanaged(abi.KeyEvent.Code, void) = .{};

    fn handle(key_event: abi.KeyEvent) std.mem.Allocator.Error!void {
        if (key_event.state == .pressed) {
            try pressKey(key_event);
        } else if (key_event.state == .released) {
            releaseKey(key_event);
        }
    }

    fn pressKey(key_event: abi.KeyEvent) std.mem.Allocator.Error!void {
        if (keys_pressed.get(.left_windows) != null or keys_pressed.get(.right_windows) != null) {
            handleWindowsKeyActions(key_event);
        }

        try keys_pressed.put(backing_allocator, key_event.code, {});
    }

    fn releaseKey(key_event: abi.KeyEvent) void {
        _ = keys_pressed.remove(key_event.code);
    }

    fn handleWindowsKeyActions(key_event: abi.KeyEvent) void {
        switch (key_event.code) {
            else => {},
        }
    }
};

fn handleKeyEvents() std.mem.Allocator.Error!void {
    while (core.keyboard.poll()) |key_event| {
        try key_handler.handle(key_event);
    }
}

fn handleMessageEvents() std.mem.Allocator.Error!void {
    while (core.gui.server.message.Tag.read()) |server_message_tag| {
        switch (server_message_tag) {
            .init_window => {
                const pid, const width, const height = core.gui.server.message.readInitWindow() orelse return;

                const buffer = try backing_allocator.alloc(abi.Color, width * height);

                for (buffer) |*color| {
                    color.* = abi.Color.black;
                }

                const window_entry = try windows.getOrPutValue(
                    backing_allocator,
                    pid,
                    .{
                        .buffer = buffer,
                        .width = width,
                        .height = height,
                    },
                );

                try windows_ordering.append(
                    backing_allocator,
                    window_entry.value_ptr,
                );
            },

            .close_window => {
                const pid = core.gui.server.message.readCloseWindow() orelse return;

                const window = windows.getPtr(pid).?;

                for (windows_ordering.items, 0..) |other_window, i| {
                    if (window == other_window) {
                        _ = windows_ordering.orderedRemove(i);

                        break;
                    }
                }

                _ = windows.remove(pid);
            },
        }
    }
}

pub fn start() noreturn {
    while (true) {
        display.clearBackground(abi.Color.black);

        handleEvents();

        drawWindows();

        display.synchronize();
    }
}

pub fn init(alloctor: std.mem.Allocator) void {
    backing_allocator = alloctor;
}
