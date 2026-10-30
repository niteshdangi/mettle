import core.future.{Context, Future, Poll};
import std.task;

type Borrowed<region r> { value: read i32 from r; polled: bool }
extend<region r> Borrowed<region r> implements Future {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.polled { Poll.Ready(*me.value) } else {
            me.polled = true
            cx.waker().wake_by_ref()
            Poll.Pending
        }
    }
}

fn main(): i32 {
    let value = 42
    if task.block_on(Borrowed(read value, false)) != 42 { return 1 }
    0
}
