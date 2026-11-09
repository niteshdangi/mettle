import core.future.{Future, Poll, Context, noop_waker}

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

async fn add(a: i32, b: i32): i32 {
    let base = 10
    var acc = a
    let x = await Count(2)
    acc = acc + x + base
    let y = await Count(1)
    acc + y + b
}
async fn tail(): i32 { await Count(1) }
async fn plain(a: i32): i32 { a + 1 }
async fn unit_body() { await Count(1); }
async fn nested(): i32 {
    let v = await add(1, 2)
    v * 2
}

// Returns the output and the number of Pending polls.
fn drive<F: Future<Output = i32>>(take future: F): (i32, i32) {
    let waker = noop_waker()
    var slot = core.pin.pin(future)
    var spins = 0
    loop {
        var cx = Context.from_waker(read waker)
        match take slot.as_mut().poll(mut cx) {
            Poll.Ready(value) => { return (value, spins) },
            Poll.Pending => { spins = spins + 1 }
        }
    }
}

async fn bump(p: ptr<mut i32>): i32 {
    unsafe { *p = *p + 1 }
    7
}

fn main(): i32 {
    let r = drive(add(1, 2))
    if r.0 != 97 { return 1 }
    if r.1 != 3 { return 2 }
    let t = drive(tail())
    if t.0 != 42 || t.1 != 1 { return 3 }
    let p = drive(plain(4))
    if p.0 != 5 || p.1 != 0 { return 4 }
    let n = drive(nested())
    if n.0 != 2 * (1 + 42 + 10 + 42 + 2) { return 5 }

    // The body runs nothing until the first poll.
    var counter = 0
    let lazy_future = bump(core.ptr.from_mut(counter))
    if counter != 0 { return 6 }
    let b = drive(lazy_future)
    if b.0 != 7 || counter != 1 { return 7 }
    0
}
