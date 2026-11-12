import core.future.{Context, Future, Poll}
import std.sys
import std.task
import std.time

extern "C" {
    unsafe fn pipe(descriptors: ptr<mut i32>): i32;
}

type PollSeparate<F> { future: ptr<mut F>; polled: bool }
// Only this task accesses the pointee, pinned in its caller's frame until teardown.
unsafe extend<F: Transferable> PollSeparate<F> implements Transferable {}
extend<F: Future> PollSeparate<F> implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.polled { return Poll.Ready(2) }
        me.polled = true
        let result = unsafe { core.pin.Pin.new_unchecked(mut *me.future).poll(mut cx) }
        match take result {
            Poll.Pending => Poll.Pending,
            Poll.Ready(_) => Poll.Ready(1)
        }
    }
}

fn delivered<F: Future + Transferable + Static>(take value: F): i32 {
    var future = value
    {
        let executor = task.executor()
        let handle = executor.spawn<i32, PollSeparate<F>>(
            PollSeparate(core.ptr.from_mut(future), false)
        )
        executor.run()
        match take capture handle.join() {
            success(polls) => { if polls != 2 { return 1 } },
            failure(_) => { return 2 }
        }
    }
    // Delivery consumed the registration waker; only the separate future remains.
    0
}

fn main(): i32 {
    if delivered(task.sleep(time.from_millis(1u64))) != 0 { return 1 }
    var descriptors = [-1i32; 2]
    if unsafe { pipe(core.ptr.from_mut(descriptors).cast<i32>()) } != 0 { return 2 }
    let input = unsafe { sys.OwnedFd.from_raw_fd(descriptors[0usize]) }
    let output = unsafe { sys.OwnedFd.from_raw_fd(descriptors[1usize]) }
    let byte = 1u8
    if unsafe { sys.write(output.as_raw_fd(), core.ptr.from_ref(byte), 1usize) } != 1isize {
        return 3
    }
    if delivered(task.readable(input.as_raw_fd())) != 0 { return 4 }
    if delivered(task.writable(output.as_raw_fd())) != 0 { return 5 }
    0
}
