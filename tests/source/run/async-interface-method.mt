import core.future.{Future, Poll, Context, noop_waker}

interface AsyncCounter {
    async fn read<region r>(receiver self: read Self from r): i32 throws i32
}

type Counter { value: i32 }

extend Counter implements AsyncCounter {
    async fn read<region r>(receiver self: read Self from r): i32 throws i32 {
        if self.value < 0 { throw self.value }
        self.value
    }
}

async fn read_generic<region r, T: AsyncCounter>(value: read T from r): i32 throws i32 {
    try await value.read()
}

async fn read_concrete<region r>(value: read Counter from r): i32 throws i32 {
    try await value.read()
}

fn drive<F: Future<Output = (i32 throws i32)>>(future: take F): (i32 throws i32) {
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

fn succeeded(result: (i32 throws i32), expected: i32): bool {
    match take result {
        success(value) => value == expected,
        failure(_) => false
    }
}

fn main(): i32 {
    let good = Counter(12)
    if !succeeded(drive(read_concrete(read good)), 12) { return 1 }
    if !succeeded(drive(read_generic(read good)), 12) { return 2 }
    let bad = Counter(-4)
    match take drive(read_generic(read bad)) {
        success(_) => { return 3 },
        failure(error) => if error != -4 { return 4 }
    }
    0
}
