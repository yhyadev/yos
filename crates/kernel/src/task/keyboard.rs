use core::{
    pin::Pin,
    task::{Context, Poll},
};

use crate::println;

use conquer_once::spin::OnceCell;

use crossbeam_queue::ArrayQueue;

use futures_util::{task::AtomicWaker, Stream};

static SCANCODE_QUEUE: OnceCell<ArrayQueue<u8>> = OnceCell::uninit();
static SCANCODE_STREAM_WAKER: AtomicWaker = AtomicWaker::new();

pub fn add_scancode(scancode: u8) {
    if let Some(queue) = SCANCODE_QUEUE.get() {
        if queue.push(scancode).is_err() {
            println!("warning: scancode queue is full, thus dropping this keyboard input");
        } else {
            SCANCODE_STREAM_WAKER.wake();
        }
    } else {
        println!("warning: scancode queue uninitialized");
    }
}

pub struct ScancodeStream {
    _private: (),
}

impl ScancodeStream {
    pub fn new() -> ScancodeStream {
        if SCANCODE_QUEUE.is_initialized() {
            panic!("initializing the scancode queue twice may cause harm");
        }

        SCANCODE_QUEUE.init_once(|| ArrayQueue::new(100));

        ScancodeStream { _private: () }
    }
}

impl Stream for ScancodeStream {
    type Item = u8;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let queue = SCANCODE_QUEUE.get().unwrap();

        if let Some(scancode) = queue.pop() {
            return Poll::Ready(Some(scancode));
        }

        SCANCODE_STREAM_WAKER.register(cx.waker());

        match queue.pop() {
            Some(scancode) => {
                SCANCODE_STREAM_WAKER.take();

                Poll::Ready(Some(scancode))
            }

            None => Poll::Pending,
        }
    }
}
