import core.future.{Future, Poll, Context, noop_waker}

interface AsyncValue {
    async fn value<region r>(receiver self: read Self from r): i32
    async fn doubled<region r>(receiver self: read Self from r) {
        (await self.value()) * 2
    }
}

type Number { value: i32 }
extend Number implements AsyncValue {
    async fn value<region r>(receiver self: read Self from r): i32 {
        self.value
    }
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
    if drive(Number(21).doubled()) == 42 { 0 } else { 1 }
}
