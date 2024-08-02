const arch = @import("../../arch.zig");
const stream = @import("../../stream.zig");

pub const Key = @import("Key.zig");

const command_port = 0x64;
const data_port = 0x60;

pub fn appendScancodeToStream() void {
    const scancode = arch.cpu.io.inb(data_port);
    stream.scancodes.append(scancode);
}

pub const Keyboard = struct {
    scancode_set: ScancodeSet = .set_1,
    layout: Layout = .us_qwerty,
    mode: Mode = .normal,

    pub const ScancodeSet = enum {
        set_1,
    };

    pub const Layout = enum {
        us_qwerty,
    };

    pub const Mode = enum {
        normal,
        extended_byte,
        /// Expected sequence is: 0xE0, 0x2A, 0xE0, 0x37
        print_screen_pressed,
        /// Expected sequence is: 0xE0 , 0xB7, 0xE0, 0xAA
        print_screen_released,
        /// Expected sequence is: 0xE1, 0x1D, 0x45, 0xE1, 0x9D, 0xC5
        /// Note: There is no scan code for "pause key released" (it behaves as if it is released as soon as it's pressed)
        pause_pressed,
    };

    pub fn map(self: *Keyboard, scancode: u8) ?Key {
        const previous_mode = self.mode;

        self.mode = .normal;

        if (previous_mode == .pause_pressed) {
            if (scancode == 197) {
                return .{ .code = .pause_break, .state = .pressed };
            } else {
                self.mode = previous_mode;

                return null;
            }
        }

        return switch (self.scancode_set) {
            .set_1 => switch (self.layout) {
                .us_qwerty => switch (scancode) {
                    1, 129 => .{ .code = .escape, .state = if (scancode >= 129) .released else .pressed },
                    2, 130 => .{ .code = .key_1, .state = if (scancode >= 129) .released else .pressed },
                    3, 131 => .{ .code = .key_2, .state = if (scancode >= 129) .released else .pressed },
                    4, 132 => .{ .code = .key_3, .state = if (scancode >= 129) .released else .pressed },
                    5, 133 => .{ .code = .key_4, .state = if (scancode >= 129) .released else .pressed },
                    6, 134 => .{ .code = .key_5, .state = if (scancode >= 129) .released else .pressed },
                    7, 135 => .{ .code = .key_6, .state = if (scancode >= 129) .released else .pressed },
                    8, 136 => .{ .code = .key_7, .state = if (scancode >= 129) .released else .pressed },
                    9, 137 => .{ .code = .key_8, .state = if (scancode >= 129) .released else .pressed },
                    10, 138 => .{ .code = .key_9, .state = if (scancode >= 129) .released else .pressed },
                    11, 139 => .{ .code = .key_0, .state = if (scancode >= 129) .released else .pressed },
                    12, 140 => .{ .code = .oem_minus, .state = if (scancode >= 129) .released else .pressed },
                    13, 141 => .{ .code = .oem_plus, .state = if (scancode >= 129) .released else .pressed },
                    14, 142 => .{ .code = .backspace, .state = if (scancode >= 129) .released else .pressed },
                    15, 143 => .{ .code = .tab, .state = if (scancode >= 129) .released else .pressed },
                    16, 144 => if (previous_mode == .normal) .{ .code = .key_q, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .prev_track, .state = if (scancode >= 129) .released else .pressed },
                    17, 145 => .{ .code = .key_w, .state = if (scancode >= 129) .released else .pressed },
                    18, 146 => .{ .code = .key_e, .state = if (scancode >= 129) .released else .pressed },
                    19, 147 => .{ .code = .key_r, .state = if (scancode >= 129) .released else .pressed },
                    20, 148 => .{ .code = .key_t, .state = if (scancode >= 129) .released else .pressed },
                    21, 149 => .{ .code = .key_y, .state = if (scancode >= 129) .released else .pressed },
                    22, 150 => .{ .code = .key_u, .state = if (scancode >= 129) .released else .pressed },
                    23, 151 => .{ .code = .key_i, .state = if (scancode >= 129) .released else .pressed },
                    24, 152 => .{ .code = .key_o, .state = if (scancode >= 129) .released else .pressed },
                    25, 153 => if (previous_mode == .normal) .{ .code = .key_p, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .next_track, .state = if (scancode >= 129) .released else .pressed },
                    26, 154 => .{ .code = .oem_4, .state = if (scancode >= 129) .released else .pressed },
                    27, 155 => .{ .code = .oem_6, .state = if (scancode >= 129) .released else .pressed },
                    28, 156 => if (previous_mode == .normal) .{ .code = .enter, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .numpad_enter, .state = if (scancode >= 129) .released else .pressed },
                    29, 157 => if (previous_mode == .normal) .{ .code = .left_control, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .right_control, .state = if (scancode >= 129) .released else .pressed },
                    30, 158 => .{ .code = .key_a, .state = if (scancode >= 129) .released else .pressed },
                    31, 159 => .{ .code = .key_s, .state = if (scancode >= 129) .released else .pressed },
                    32, 160 => if (previous_mode == .normal) .{ .code = .key_d, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .mute, .state = if (scancode >= 129) .released else .pressed },
                    33, 161 => if (previous_mode == .normal) .{ .code = .key_f, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .calculator, .state = if (scancode >= 129) .released else .pressed },
                    34, 162 => if (previous_mode == .normal) .{ .code = .key_g, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .play, .state = if (scancode >= 129) .released else .pressed },
                    35, 163 => .{ .code = .key_h, .state = if (scancode >= 129) .released else .pressed },
                    36, 164 => if (previous_mode == .normal) .{ .code = .key_j, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .stop, .state = if (scancode >= 129) .released else .pressed },
                    37, 165 => .{ .code = .key_k, .state = if (scancode >= 129) .released else .pressed },
                    38, 166 => .{ .code = .key_l, .state = if (scancode >= 129) .released else .pressed },
                    39, 167 => .{ .code = .oem_1, .state = if (scancode >= 129) .released else .pressed },
                    40, 168 => .{ .code = .oem_3, .state = if (scancode >= 129) .released else .pressed },
                    41, 169 => .{ .code = .oem_7, .state = if (scancode >= 129) .released else .pressed },

                    42, 170 => blk: {
                        if (previous_mode == .normal) {
                            break :blk .{ .code = .left_shift, .state = if (scancode >= 129) .released else .pressed };
                        } else if (previous_mode == .extended_byte) {
                            self.mode = .print_screen_pressed;

                            break :blk null;
                        } else if (previous_mode == .print_screen_released) {
                            break :blk .{ .code = .print_screen, .state = .released };
                        }
                    },

                    43, 171 => .{ .code = .oem_5, .state = if (scancode >= 129) .released else .pressed },
                    44, 172 => .{ .code = .key_z, .state = if (scancode >= 129) .released else .pressed },
                    45, 173 => .{ .code = .key_x, .state = if (scancode >= 129) .released else .pressed },
                    46, 174 => if (previous_mode == .normal) .{ .code = .key_c, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .volume_down, .state = if (scancode >= 129) .released else .pressed },
                    47, 175 => .{ .code = .key_v, .state = if (scancode >= 129) .released else .pressed },
                    48, 176 => if (previous_mode == .normal) .{ .code = .key_b, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .volume_up, .state = if (scancode >= 129) .released else .pressed },
                    49, 177 => .{ .code = .key_n, .state = if (scancode >= 129) .released else .pressed },
                    50, 178 => if (previous_mode == .normal) .{ .code = .key_m, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .www_home, .state = if (scancode >= 129) .released else .pressed },
                    51, 179 => .{ .code = .oem_comma, .state = if (scancode >= 129) .released else .pressed },
                    52, 180 => .{ .code = .oem_period, .state = if (scancode >= 129) .released else .pressed },
                    53, 181 => if (previous_mode == .normal) .{ .code = .oem_2, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .numpad_divide, .state = if (scancode >= 129) .released else .pressed },
                    54, 182 => .{ .code = .right_shift, .state = if (scancode >= 129) .released else .pressed },

                    55, 183 => blk: {
                        if (previous_mode == .normal) {
                            break :blk .{ .code = .numpad_multiply, .state = if (scancode >= 129) .released else .pressed };
                        } else if (previous_mode == .extended_byte and scancode == 183) {
                            self.mode = .print_screen_released;

                            break :blk null;
                        } else if (previous_mode == .print_screen_pressed) {
                            break :blk .{ .code = .print_screen, .state = .pressed };
                        }
                    },

                    56, 184 => if (previous_mode == .normal) .{ .code = .left_alt, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .right_alt, .state = if (scancode >= 129) .released else .pressed },
                    57, 185 => .{ .code = .spacebar, .state = if (scancode >= 129) .released else .pressed },
                    58, 186 => .{ .code = .caps_lock, .state = if (scancode >= 129) .released else .pressed },
                    59, 187 => .{ .code = .f1, .state = if (scancode >= 129) .released else .pressed },
                    60, 188 => .{ .code = .f2, .state = if (scancode >= 129) .released else .pressed },
                    61, 189 => .{ .code = .f3, .state = if (scancode >= 129) .released else .pressed },
                    62, 190 => .{ .code = .f4, .state = if (scancode >= 129) .released else .pressed },
                    63, 191 => .{ .code = .f5, .state = if (scancode >= 129) .released else .pressed },
                    64, 192 => .{ .code = .f6, .state = if (scancode >= 129) .released else .pressed },
                    65, 193 => .{ .code = .f7, .state = if (scancode >= 129) .released else .pressed },
                    66, 194 => .{ .code = .f8, .state = if (scancode >= 129) .released else .pressed },
                    67, 195 => .{ .code = .f9, .state = if (scancode >= 129) .released else .pressed },
                    68, 196 => .{ .code = .f10, .state = if (scancode >= 129) .released else .pressed },
                    69, 197 => .{ .code = .numpad_lock, .state = if (scancode >= 129) .released else .pressed },
                    70, 198 => .{ .code = .scroll_lock, .state = if (scancode >= 129) .released else .pressed },
                    71, 199 => if (previous_mode == .normal) .{ .code = .numpad_7, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .home, .state = if (scancode >= 129) .released else .pressed },
                    72, 200 => if (previous_mode == .normal) .{ .code = .numpad_8, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .arrow_up, .state = if (scancode >= 129) .released else .pressed },
                    73, 201 => if (previous_mode == .normal) .{ .code = .numpad_9, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .page_up, .state = if (scancode >= 129) .released else .pressed },
                    74, 202 => .{ .code = .numpad_subtract, .state = if (scancode >= 129) .released else .pressed },
                    75, 203 => if (previous_mode == .normal) .{ .code = .numpad_4, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .arrow_left, .state = if (scancode >= 129) .released else .pressed },
                    76, 204 => .{ .code = .numpad_5, .state = if (scancode >= 129) .released else .pressed },
                    77, 205 => if (previous_mode == .normal) .{ .code = .numpad_6, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .arrow_right, .state = if (scancode >= 129) .released else .pressed },
                    78, 206 => .{ .code = .numpad_add, .state = if (scancode >= 129) .released else .pressed },
                    79, 207 => if (previous_mode == .normal) .{ .code = .numpad_1, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .end, .state = if (scancode >= 129) .released else .pressed },
                    80, 208 => if (previous_mode == .normal) .{ .code = .numpad_2, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .arrow_down, .state = if (scancode >= 129) .released else .pressed },
                    81, 209 => if (previous_mode == .normal) .{ .code = .numpad_3, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .page_down, .state = if (scancode >= 129) .released else .pressed },
                    82, 210 => if (previous_mode == .normal) .{ .code = .numpad_0, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .insert, .state = if (scancode >= 129) .released else .pressed },
                    83, 211 => if (previous_mode == .normal) .{ .code = .numpad_period, .state = if (scancode >= 129) .released else .pressed } else .{ .code = .delete, .state = if (scancode >= 129) .released else .pressed },
                    87, 215 => .{ .code = .f11, .state = if (scancode >= 129) .released else .pressed },
                    88, 216 => .{ .code = .f12, .state = if (scancode >= 129) .released else .pressed },
                    91, 219 => .{ .code = .left_windows, .state = if (scancode >= 129) .released else .pressed },
                    92, 220 => .{ .code = .right_windows, .state = if (scancode >= 129) .released else .pressed },
                    93, 221 => .{ .code = .apps, .state = if (scancode >= 129) .released else .pressed },

                    224 => blk: {
                        if (previous_mode == .normal) {
                            self.mode = .extended_byte;
                        } else {
                            self.mode = previous_mode;
                        }

                        break :blk null;
                    },

                    225 => blk: {
                        self.mode = .pause_pressed;

                        break :blk null;
                    },

                    else => .{ .code = .unknown, .state = .pressed },
                },
            },
        };
    }
};
