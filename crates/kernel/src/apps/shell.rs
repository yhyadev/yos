use crate::task::keyboard::ScancodeStream;
use crate::{print, println};

use alloc::string::String;
use futures_util::StreamExt;

use pc_keyboard::layouts::Us104Key;
use pc_keyboard::{DecodedKey, HandleControl, Keyboard, ScancodeSet1};

pub async fn run() {
    let mut scancodes = ScancodeStream::new();
    let mut keyboard = Keyboard::new(ScancodeSet1::new(), Us104Key, HandleControl::Ignore);

    loop {
        print!("> ");

        let command = read_line(&mut scancodes, &mut keyboard).await;

        if command.is_empty() {
            continue;
        }

        match command {
            _ => println!("shell: unknown command: {}", command),
        }
    }
}

async fn read_line(
    scancodes: &mut ScancodeStream,
    keyboard: &mut Keyboard<Us104Key, ScancodeSet1>,
) -> String {
    let mut input = String::new();

    while let Some(scancode) = scancodes.next().await {
        if let Ok(Some(key_event)) = keyboard.add_byte(scancode) {
            if let Some(decoded_key) = keyboard.process_keyevent(key_event) {
                match decoded_key {
                    DecodedKey::Unicode(character) => {
                        if character == '\n' {
                            println!("");

                            break;
                        }

                        if character == '\x08' && !input.is_empty() {
                            input.pop();

                            print!("{}", character);
                        }

                        if !character.is_control() {
                            input.push(character);

                            print!("{}", character);
                        }
                    }

                    DecodedKey::RawKey(_) => (),
                }
            }
        }
    }

    input
}

