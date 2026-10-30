import core::future::{Future, Poll, Context, noop_waker};

type Count { left: i32 }
impl Count implements Future {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.left == 0 { Poll::Ready(42) } else {
            me.left = me.left - 1
            cx.waker().wake_by_ref()
            Poll::Pending
        }
    }
}

// Returns the output and the number of Pending polls.
fn drive<F: Future<Output = i32>>(future: take F): (i32, i32) {
    let waker = noop_waker()
    var slot = core::pin::pin(future)
    var spins = 0
    loop {
        var cx = Context::from_waker(read waker)
        match take slot.as_mut().poll(mut cx) {
            Poll::Ready(value) => { return (value, spins) },
            Poll::Pending => { spins = spins + 1 }
        }
    }
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
