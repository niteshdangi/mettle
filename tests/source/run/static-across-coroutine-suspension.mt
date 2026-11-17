module source_helpers;
import core.future.{Future, Poll, Context}

static VALUE: i32 = 21

type YieldOnce { yielded: bool }
extend YieldOnce implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.yielded {
            Poll.Ready(VALUE)
        } else {
            me.yielded = true
            cx.waker().wake_by_ref()
            Poll.Pending
        }
    }
}

async fn answer(): i32 {
    let value = await YieldOnce(false)
    value + VALUE
}

fn drive<F: Future<Output = i32>>(take future: F): i32 {
    source_helpers.drive!(future)
}

fn main(): i32 {
    if drive(answer()) == 42 { 0 } else { 1 }
}
