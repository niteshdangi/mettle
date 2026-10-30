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

async fn sum_while(n: i32): i32 {
    var i = 0
    var total = 0
    while i < n {
        let v = await Count(1)
        total = total + v + i
        i = i + 1
    }
    total
}

async fn find(limit: i32): i32 {
    var k = 0
    loop {
        let v = await Count(1)
        k = k + 1
        if k >= limit { break k * 100 + v }
    }
}

async fn labeled(): i32 {
    var total = 0
    var i = 0
    label outer: while i < 4 {
        i = i + 1
        let v = await Count(1)
        var j = 0
        while j < 3 {
            j = j + 1
            if v == 42 && j == 2 { continue label outer }
            total = total + j
        }
    }
    total
}

async fn ranged(n: i32): i32 {
    var total = 0
    for i in 0..n {
        let v = await Count(1)
        total = total + i * v
    }
    total
}

async fn ranged_break(n: i32): i32 {
    var total = 0
    for i in 0..n {
        let v = await Count(1)
        if i == 2 { break }
        total = total + i * v
    }
    total
}

// An inclusive range ending at the type's maximum must not step past it.
async fn inclusive(low: i32, high: i32): i32 {
    var total = 0
    for i in low..=high {
        let v = await Count(1)
        if i == low + 1 { continue }
        total = total + 1
    }
    total
}

async fn block_scope(): i32 {
    var total = 1
    let base = 10
    {
        let a = await Count(1)
        total = total + a
    }
    let b = await Count(0)
    total + b + base
}

async fn join(flag: bool): i32 {
    var total = 0
    if flag {
        total = total + await Count(1)
    } else {
        total = 7
    }
    total + 1
}

type Guard {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter = *self.counter + 100 } }
}

async fn guarded(p: ptr<mut i32>): i32 {
    let guard = Guard(p)
    var i = 0
    while i < 5 {
        let c = guard.counter
        unsafe { *c = *c + 1 }
        let v = await Count(1)
        i = i + v - 41
    }
    i
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

// Polls twice and drops the unfinished future.
fn abandon<F: Future<Output = i32>>(future: take F): Unit {
    let waker = noop_waker()
    var slot = core::pin::pin(future)
    var polls = 0
    while polls < 2 {
        var cx = Context::from_waker(read waker)
        match take slot.as_mut().poll(mut cx) {
            Poll::Ready(value) => { return },
            Poll::Pending => { polls = polls + 1 }
        }
    }
}

fn main(): i32 {
    let a = drive(sum_while(3))
    if a.0 != 3 * 42 + 3 || a.1 != 3 { return 1 }
    let b = drive(find(3))
    if b.0 != 342 || b.1 != 3 { return 2 }
    let c = drive(labeled())
    if c.0 != 4 || c.1 != 4 { return 3 }
    let d = drive(ranged(4))
    if d.0 != 42 * 6 || d.1 != 4 { return 4 }
    let e = drive(ranged_break(5))
    if e.0 != 42 || e.1 != 3 { return 5 }
    let i = drive(inclusive(1, 4))
    if i.0 != 3 || i.1 != 4 { return 11 }
    let j = drive(inclusive(2147483645, 2147483647))
    if j.0 != 2 || j.1 != 3 { return 12 }
    let f = drive(block_scope())
    if f.0 != 43 + 42 + 10 || f.1 != 1 { return 6 }
    let g = drive(join(true))
    if g.0 != 43 || g.1 != 1 { return 7 }
    let h = drive(join(false))
    if h.0 != 8 || h.1 != 0 { return 8 }

    // The saved local is dropped exactly once, whether the loop finishes or
    // the future is dropped between iterations.
    var counter = 0
    let done = drive(guarded(core::ptr::from_mut(counter)))
    if done.0 != 5 || counter != 5 + 100 { return 9 }
    var cancelled = 0
    abandon(guarded(core::ptr::from_mut(cancelled)))
    if cancelled != 2 + 100 { return 10 }
    0
}
