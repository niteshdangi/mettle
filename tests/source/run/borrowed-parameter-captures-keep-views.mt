import core.future.{Future, Poll, Context, noop_waker}

// Async bodies and owning closures capture a borrowed non-Copy parameter as a
// view of the caller's value instead of moving out of the borrowed place.

type Counter { value: i32 }
fn sync_plain(c: read Counter): i32 { c.value }
async fn plain(c: read Counter): i32 { c.value }
async fn forward(value: read Counter): i32 { await plain(value) + sync_plain(value) }
fn closure_view(value: read Counter): i32 {
    let f = take fn(): i32 { sync_plain(value) }
    f()
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
    let c = Counter(4)
    if drive(forward(read c)) != 8 { return 1 }
    if closure_view(read c) != 4 { return 2 }
    0
}
