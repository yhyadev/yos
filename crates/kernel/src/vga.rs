use lazy_static::lazy_static;

use spin::Mutex;

use volatile::Volatile;

use core::fmt;

#[derive(Clone, Copy)]
#[repr(u8)]
pub enum VGAColor {
    Black = 0,
    Blue,
    Green,
    Cyan,
    Red,
    Magenta,
    Brown,
    LightGray,
    DarkGray,
    LightBlue,
    LightGreen,
    LightCyan,
    LightRed,
    Pink,
    Yellow,
    White,
}

#[derive(Clone, Copy)]
#[repr(transparent)]
pub struct VGAColorCode(u8);

impl VGAColorCode {
    pub const fn new(fg: VGAColor, bg: VGAColor) -> VGAColorCode {
        VGAColorCode((bg as u8) << 4 | (fg as u8))
    }
}

#[derive(Clone, Copy)]
#[repr(C)]
struct VGAScreenCharacter {
    content: u8,
    color_code: VGAColorCode,
}

#[repr(transparent)]
struct VGABuffer {
    characters: [[Volatile<VGAScreenCharacter>; VGABuffer::WIDTH]; VGABuffer::HEIGHT],
}

impl VGABuffer {
    const WIDTH: usize = 80;
    const HEIGHT: usize = 25;
}

lazy_static! {
    pub static ref GLOBAL_VGA_WRITER: Mutex<VGAWriter> = Mutex::new(VGAWriter::new(
        VGAColorCode::new(VGAColor::White, VGAColor::Black)
    ));
}

#[macro_export]
macro_rules! print {
    ($($arg:tt)*) => {{
        $crate::vga::_print(format_args!($($arg)*));
    }};
}

#[macro_export]
macro_rules! println {
    () => {
        $crate::print!("\n");
    };

    ($($arg:tt)*) => {
        $crate::print!("{}\n", format_args!($($arg)*));
    };
}

pub fn _print(args: fmt::Arguments) {
    use core::fmt::Write;
    GLOBAL_VGA_WRITER.lock().write_fmt(args).unwrap();
}

pub struct VGAWriter {
    row: usize,
    column: usize,
    color_code: VGAColorCode,
    buffer: &'static mut VGABuffer,
}

impl VGAWriter {
    pub fn new(color_code: VGAColorCode) -> VGAWriter {
        VGAWriter {
            row: 0,
            column: 0,
            color_code,
            buffer: unsafe { &mut *(0xb8000 as *mut VGABuffer) },
        }
    }

    fn write_new_line(&mut self) {
        if self.row == VGABuffer::HEIGHT - 1 {
            for row in 1..VGABuffer::HEIGHT {
                for column in 0..VGABuffer::WIDTH {
                    self.buffer.characters[row - 1][column]
                        .write(self.buffer.characters[row][column].read());
                }
            }

            self.clear_row(self.row);
        } else {
            self.row += 1;
        }

        self.column = 0;
    }

    fn clear_row(&mut self, row: usize) {
        let blank = VGAScreenCharacter {
            content: b' ',
            color_code: self.color_code,
        };

        for column in 0..VGABuffer::WIDTH {
            self.buffer.characters[row][column].write(blank);
        }
    }

    pub fn write_byte(&mut self, byte: u8) {
        if self.column >= VGABuffer::WIDTH {
            self.write_new_line();
        }

        self.buffer.characters[self.row][self.column].write(VGAScreenCharacter {
            content: byte,
            color_code: self.color_code,
        });

        self.column += 1;
    }

    pub fn write_char(&mut self, ch: char) {
        match ch as u8 {
            b'\n' => self.write_new_line(),

            0x20..=0x7e => self.write_byte(ch as u8),

            // TODO: Handle non-ASCII characters
            _ => self.write_byte(0xfe),
        }
    }
}

impl core::fmt::Write for VGAWriter {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        for ch in s.chars() {
            self.write_char(ch);
        }

        Ok(())
    }
}
