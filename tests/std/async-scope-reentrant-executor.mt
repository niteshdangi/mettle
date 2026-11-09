import core.future.{Context, Future, Poll}
import std.task

type ReentrantRun {
    executor: ptr<mut task.Executor>
    blocking: bool
}

extend ReentrantRun implements Future {
    type Output = Unit
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<Unit> {
        let me = unsafe { self.get_unchecked_mut() }
        cx.waker().wake_by_ref()
        if me.blocking {
            unsafe { (*me.executor).run() }
        } else {
            let _polls = unsafe { (*me.executor).run_until_stalled() }
        }
        Poll.Ready(())
    }
}

// Safety: both tasks finish and are destroyed before main drops the executor;
// this local executor never transfers its future to a polling thread.
unsafe extend ReentrantRun implements Transferable {}

fn main(): i32 {
    var executor = task.executor()
    let executor_ptr = core.ptr.from_mut(mut executor)
    let blocking = executor.spawn(ReentrantRun(executor_ptr, true))
    let nonblocking = executor.spawn(ReentrantRun(executor_ptr, false))
    executor.run()

    match take capture blocking.join() {
        failure(task.JoinError.Panicked(code)) => { if code != 101 { return 1 } },
        _ => { return 2 }
    }
    match take capture nonblocking.join() {
        failure(task.JoinError.Panicked(code)) => { if code != 101 { return 3 } },
        _ => { return 4 }
    }
    0
}
