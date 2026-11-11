module source_helpers;
import core.future.{Future, Poll, Context}

type Count { left: i32 }
extend Count implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.left == 0 { Poll.Ready(42) } else {
            me.left = me.left - 1
            cx.waker().wake_by_ref()
            Poll.Pending
        }
    }
}

// Returns the output and the number of Pending polls.
fn drive<F: Future<Output = i32>>(take future: F): (i32, i32) {
    source_helpers.drive_counted!(future)
}

fn main(): i32 {
    let seed = 1
    let block = async {
        let x = await Count(1)
        x + seed
    }
    let r = drive(block)
    if r.0 != 43 || r.1 != 1 { return 1 }
    let make = async fn(a: i32): i32 {
        let x = await Count(0)
        x + a
    }
    let s = drive(make(2))
    if s.0 != 44 || s.1 != 0 { return 2 }
    0
}
