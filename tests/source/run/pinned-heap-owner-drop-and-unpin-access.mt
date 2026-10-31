import core.future.{Future, Poll, Context, noop_waker}
type Counter { log: ptr<mut i32>; n: i32; drop { unsafe { *self.log = *self.log + 1 } } }
type YieldOnce { value: i32; yielded: bool }
extend YieldOnce implements Future {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.yielded { Poll.Ready(me.value) } else {
            me.yielded = true
            Poll.Pending
        }
    }
}
async fn seven(): i32 { await YieldOnce(7, false) }
async fn outer(): i32 {
    let f = alloc.boxed.pin(seven())
    await f
}
fn drive<F: Future>(future: take F): F.Output {
    let waker = noop_waker()
    var slot = core.pin.pin(future)
    loop {
        var cx = Context.from_waker(read waker)
        match take slot.as_mut().poll(mut cx) {
            Poll.Ready(value) => { return value },
            Poll.Pending => {}
        }
    }
}
fn main(): i32 {
    var drops = 0
    let log = core.ptr.from_mut(drops)
    var p = alloc.boxed.pin(Counter(log, 3))
    p.get_mut().n = 4
    if p.get_ref().n != 4 { return 1 }
    let b = p.into_inner()
    if b.get().n != 4 { return 2 }
    { let moved = b }
    if drops != 1 { return 3 }
    { let r = (heap Counter(log, 5)).into_pinned() }
    if drops != 2 { return 4 }
    if drive(outer()) != 7 { return 5 }
    let direct = alloc.boxed.pin(seven())
    if drive(direct) != 7 { return 6 }
    0
}
