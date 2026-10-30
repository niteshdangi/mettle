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

async fn pick(flag: bool): i32 {
    let base = 5
    if flag {
        let v = await Count(1)
        v + base
    } else {
        base
    }
}
async fn matched(n: i32): i32 {
    match n {
        0 => { await Count(1) },
        1 => { let a = await Count(0); a + 1 },
        _ => { n }
    }
}
async fn early(n: i32): i32 {
    if n < 0 { return 0 - 1 }
    let v = await Count(1)
    v + n
}
async fn sub(): i32 {
    let k = 2
    k * await Count(1) + await Count(0)
}
async fn condition(): i32 {
    if await Count(0) == 42 { await Count(1) } else { 0 }
}
async fn pattern(): i32 {
    let (a, b) = (await Count(1), 1)
    a + b
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
    let a = drive(pick(true))
    if a.0 != 47 || a.1 != 1 { return 1 }
    let b = drive(pick(false))
    if b.0 != 5 || b.1 != 0 { return 2 }
    let c = drive(matched(0))
    if c.0 != 42 || c.1 != 1 { return 3 }
    let d = drive(matched(1))
    if d.0 != 43 || d.1 != 0 { return 4 }
    let e = drive(matched(7))
    if e.0 != 7 || e.1 != 0 { return 5 }
    let f = drive(early(0 - 3))
    if f.0 != 0 - 1 || f.1 != 0 { return 6 }
    let g = drive(early(3))
    if g.0 != 45 || g.1 != 1 { return 7 }
    let h = drive(sub())
    if h.0 != 126 || h.1 != 1 { return 8 }
    let i = drive(condition())
    if i.0 != 42 || i.1 != 1 { return 9 }
    let j = drive(pattern())
    if j.0 != 43 || j.1 != 1 { return 10 }
    0
}
