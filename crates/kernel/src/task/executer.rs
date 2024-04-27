use core::task::{Context, Poll, Waker};

use super::{Task, TaskId};

use alloc::collections::BTreeMap;
use alloc::sync::Arc;

use alloc::task::Wake;
use crossbeam_queue::ArrayQueue;

pub struct Executer {
    tasks: BTreeMap<TaskId, Task>,
    task_queue: Arc<ArrayQueue<TaskId>>,
    waker_cache: BTreeMap<TaskId, Waker>,
}

impl Executer {
    pub fn new() -> Executer {
        Executer {
            tasks: BTreeMap::new(),
            task_queue: Arc::new(ArrayQueue::new(100)),
            waker_cache: BTreeMap::new(),
        }
    }

    pub fn spawn(&mut self, task: Task) {
        let task_id = task.id;

        if self.tasks.insert(task_id, task).is_some() {
            panic!("task with the same id is already in the map");
        }

        self.task_queue.push(task_id).expect("task queue is full");
    }

    pub fn run(&mut self) -> ! {
        loop {
            self.run_ready_tasks();
            self.sleep_while_idle();
        }
    }

    fn run_ready_tasks(&mut self) {
        while let Some(task_id) = self.task_queue.pop() {
            let Some(task) = self.tasks.get_mut(&task_id) else {
                continue;
            };

            let waker = self
                .waker_cache
                .entry(task_id)
                .or_insert_with(|| TaskWaker::new(task_id, self.task_queue.clone()));

            let mut context = Context::from_waker(&waker);

            match task.poll(&mut context) {
                Poll::Ready(()) => {
                    self.tasks.remove(&task_id);
                    self.waker_cache.remove(&task_id);
                }

                Poll::Pending => (),
            }
        }
    }

    fn sleep_while_idle(&mut self) {
        x86_64::instructions::interrupts::disable();

        if self.task_queue.is_empty() {
            x86_64::instructions::interrupts::enable_and_hlt();
        } else {
            x86_64::instructions::interrupts::enable();
        }
    }
}

struct TaskWaker {
    task_id: TaskId,
    task_queue: Arc<ArrayQueue<TaskId>>,
}

impl TaskWaker {
    fn new(task_id: TaskId, task_queue: Arc<ArrayQueue<TaskId>>) -> Waker {
        Waker::from(Arc::new(TaskWaker {
            task_id,
            task_queue,
        }))
    }
}

impl Wake for TaskWaker {
    fn wake(self: Arc<Self>) {
        self.task_queue
            .push(self.task_id)
            .expect("task queue is full");
    }

    fn wake_by_ref(self: &Arc<Self>) {
        self.task_queue
            .push(self.task_id)
            .expect("task queue is full");
    }
}
