pub const Syscode = enum(usize) {
    write,
    read,
    open,
    close,
    poll,
    exit,
    kill,
    getpid,
    fork,
    execv,
    scrput,
    scrget,
    scrwidth,
    scrheight,
    mmap,
    munmap,
};

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

pub const KeyEvent = packed struct {
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
