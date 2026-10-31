import core.future.{Future, Poll, Context, noop_waker}
type C { v: i32 }
async fn bump(c: mut C, by: i32): i32 {
    c.v = c.v + by
    c.v
}
fn drive<F: Future<Output = i32>>(future: take F): i32 {
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
    var c = C(1)
    if drive(bump(mut c, 2)) != 3 { return 1 }
    if c.v != 3 { return 2 }
    0
}
