import core.future.{Future, Poll, Context, noop_waker}

async fn read_value(read value: i32): i32 { value + 1 }

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
    let value = 41
    let boxed = alloc.boxed.new(read_value(read value))
    let future = boxed.into_inner()
    if drive(future) == 42 { 0 } else { 1 }
}
