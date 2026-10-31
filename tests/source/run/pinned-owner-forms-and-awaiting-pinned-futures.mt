import core.future.{Future, Poll, Context, noop_waker}
type Counter { log: ptr<mut i32>; n: i32; drop { unsafe { *self.log = *self.log + 1 } } }
async fn seven(): i32 { 7 }
async fn outer(): i32 {
    let f: pinned heap any Future<Output = i32> = pinned heap seven()
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
    var p: pinned heap Counter = pinned heap Counter(log, 3)
    let s: pinned shared Counter = pinned shared Counter(log, 4)
    let l: pinned local shared Counter = pinned local shared Counter(log, 5)
    if p.get_ref().n + s.get_ref().n + l.get_ref().n != 12 { return 1 }
    if drive(outer()) != 7 { return 2 }
    0
}
