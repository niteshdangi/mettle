import core.future.{Future, Poll, Context, noop_waker}

async fn compute(value: i32): i32 throws i32 {
    if value < 0 { throw value }
    value + 1
}

async fn propagate(value: i32): i32 throws i32 {
    try await compute(value)
}

fn drive<F: Future<Output = (Outcome<i32, i32>)>>(take future: F): (Outcome<i32, i32>) {
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
    match take drive(propagate(4)) {
        success(value) => if value != 5 { return 1 },
        failure(_) => { return 2 }
    }
    match take drive(propagate(-3)) {
        success(_) => { return 3 },
        failure(error) => if error != -3 { return 4 }
    }
    0
}
