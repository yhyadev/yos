const std = @import("std");

const arch = @import("arch.zig");

pub const syscall0 = arch.cpu.syscall.syscall0;
pub const syscall1 = arch.cpu.syscall.syscall1;
pub const syscall2 = arch.cpu.syscall.syscall2;
pub const syscall3 = arch.cpu.syscall.syscall3;
pub const syscall4 = arch.cpu.syscall.syscall4;
pub const syscall5 = arch.cpu.syscall.syscall5;
pub const syscall6 = arch.cpu.syscall.syscall6;

pub const console = struct {
    pub const Writer = std.io.Writer(void, error{}, printImpl);
    pub const writer = Writer{ .context = {} };

    pub fn print(comptime format: []const u8, arguments: anytype) void {
        std.fmt.format(writer, format, arguments) catch unreachable;
    }

    fn printImpl(_: void, bytes: []const u8) !usize {
        return write(0, 0, bytes);
    }
};

pub const screen = struct {
    pub const Color = packed struct(u32) {
        b: u8,
        g: u8,
        r: u8,
        padding: u8 = 0,

        pub const white: Color = .{ .r = 255, .g = 255, .b = 255 };
        pub const black: Color = .{ .r = 0, .g = 0, .b = 0 };
        pub const red: Color = .{ .r = 255, .g = 0, .b = 0 };
        pub const blue: Color = .{ .r = 0, .g = 0, .b = 255 };
        pub const green: Color = .{ .r = 0, .g = 255, .b = 0 };
    };

    pub fn put(x: usize, y: usize, color: Color) void {
        _ = syscall3(.scrput, x, y, @as(u32, @bitCast(color)));
    }

    pub fn get(x: usize, y: usize) Color {
        return @bitCast(@as(u32, @intCast(syscall2(.scrget, x, y))));
    }

    pub fn width() usize {
        return syscall0(.scrwidth);
    }

    pub fn height() usize {
        return syscall0(.scrheight);
    }
};

pub const keyboard = struct {
    pub const Key = packed struct {
        code: Code,
        state: State,

        pub const Code = enum(u7) {
            f1,
            f2,
            f3,
            f4,
            f5,
            f6,
            f7,
            f8,
            f9,
            f10,
            f11,
            f12,

            key_1,
            key_2,
            key_3,
            key_4,
            key_5,
            key_6,
            key_7,
            key_8,
            key_9,
            key_0,

            key_a,
            key_b,
            key_c,
            key_d,
            key_e,
            key_f,
            key_g,
            key_h,
            key_i,
            key_j,
            key_k,
            key_l,
            key_m,
            key_n,
            key_o,
            key_p,
            key_q,
            key_r,
            key_s,
            key_t,
            key_u,
            key_v,
            key_w,
            key_x,
            key_y,
            key_z,

            insert,
            enter,
            home,
            end,
            page_up,
            page_down,
            delete,
            tab,
            backspace,
            escape,
            spacebar,
            print_screen,
            @"return",
            /// 'Apps' Key (aka 'Menu' or 'Right-Click')
            apps,
            /// Alt + Print_screen
            system_request,
            /// Pause / Break
            pause_break,
            caps_lock,
            scroll_lock,

            left_control,
            left_shift,
            left_alt,
            left_windows,

            right_control,
            right_control_2,
            right_shift,
            right_alt,
            right_alt_2,
            right_windows,

            arrow_up,
            arrow_down,
            arrow_left,
            arrow_right,

            numpad_add,
            numpad_subtract,
            numpad_divide,
            numpad_multiply,
            numpad_lock,
            numpad_period,
            numpad_enter,
            numpad_0,
            numpad_1,
            numpad_2,
            numpad_3,
            numpad_4,
            numpad_5,
            numpad_6,
            numpad_7,
            numpad_8,
            numpad_9,

            /// The US ANSI Semicolon/Colon key
            oem_1,
            /// US ANSI `/?` Key
            oem_2,
            /// The US ANSI Single-Quote/At key
            oem_3,
            /// US ANSI Left-Square-Bracket key
            oem_4,
            /// US ANSI Right-Square-Bracket key
            oem_6,
            /// US ANSI Backslash Key / UK ISO Backslash Key
            oem_5,
            /// The UK/ISO Hash/Tilde key (ISO layout only)
            oem_7,
            /// Symbol Key to the left of `key_1`
            oem_8,
            /// Extra JIS key (0x7B)
            oem_9,
            /// Extra JIS key (0x79)
            oem_10,
            /// Extra JIS key (0x70)
            oem_11,
            /// Extra JIS symbol key (0x73)
            oem_12,
            /// Extra JIS symbol key (0x7D)
            oem_13,
            /// US Minus/Underscore Key (right of 'key_0')
            oem_minus,
            /// US Equals/Plus Key (right of 'oem_minus')
            oem_plus,
            /// US ANSI `,<` key
            oem_comma,
            /// US ANSI `.>` Key
            oem_period,

            prev_track,
            next_track,
            mute,
            play,
            stop,
            volume_down,
            volume_up,
            calculator,
            www_home,

            unknown,
        };

        pub const State = enum(u1) {
            released,
            pressed,
        };
    };

    pub fn poll() ?Key {
        const maybe_key: isize = @bitCast(syscall0(.keypoll));

        if (maybe_key == -1) {
            return null;
        }

        return @bitCast(@as(u8, @intCast(maybe_key)));
    }
};

pub fn exit(status: u8) noreturn {
    _ = syscall1(.exit, status);

    unreachable;
}

pub fn write(fd: usize, offset: usize, buffer: []const u8) usize {
    return syscall4(.write, fd, offset, @intFromPtr(buffer.ptr), buffer.len);
}

pub fn read(fd: usize, offset: usize, buffer: []u8) usize {
    return syscall4(.read, fd, offset, @intFromPtr(buffer.ptr), buffer.len);
}

pub fn open(path: []const u8) isize {
    return @bitCast(syscall2(.open, @intFromPtr(path.ptr), path.len));
}

pub fn close(fd: usize) isize {
    return @bitCast(syscall2(.close, fd));
}

pub fn getpid() usize {
    return syscall0(.getpid);
}

pub fn kill(pid: usize) void {
    _ = syscall1(.kill, pid);
}

pub fn fork() usize {
    return syscall0(.fork);
}

pub fn execv(argv: []const [*:0]const u8) isize {
    return @bitCast(syscall2(.execv, @intFromPtr(argv.ptr), argv.len));
}
