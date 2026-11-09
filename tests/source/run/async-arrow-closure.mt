import core.future.{Future, Poll, Context, noop_waker}

fn drive<F: Future<Output = i32>>(take future: F): i32 {
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
    let captured = 5
    let add = async fn(value: i32): i32 => value + captured
    if drive(add(7)) != 12 { return 1 }
    0
}
