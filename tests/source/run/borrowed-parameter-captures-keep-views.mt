import core.future.{Future, Poll, Context, noop_waker}

// Async bodies and owning closures capture a borrowed non-Copy parameter as a
// view of the caller's value instead of moving out of the borrowed place.
// Unsized slice parameters are always captured as views.

type Counter { value: i32 }
fn sync_plain(read c: Counter): i32 { c.value }
async fn plain(read c: Counter): i32 { c.value }
async fn forward(read value: Counter): i32 { await plain(value) + sync_plain(value) }
async fn total(read bytes: [u8]): usize { bytes.len() + bytes[0usize] as usize }
async fn fill(mut bytes: [u8]): Unit { bytes[0usize] = 7u8 }
fn closure_view(read value: Counter): i32 {
    let f = take fn(): i32 { sync_plain(value) }
    f()
}

fn drive<F: Future>(take future: F): F.Output {
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
    var bytes = [1u8; 3]
    if drive(total(bytes)) != 4usize { return 3 }
    drive(fill(bytes))
    if bytes[0usize] != 7u8 { return 4 }
    0
}
