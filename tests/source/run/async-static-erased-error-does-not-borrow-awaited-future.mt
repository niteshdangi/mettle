import alloc.boxed.Box
import core.future.{Future, Poll, Context, noop_waker}

interface Show { fn value(): i32; }
type Plain { value: i32 }
extend Plain implements Show { fn value(): i32 { self.value } }
type Fault { payload: Box<any Show> }
type Input { value: i32 }

async fn compute(read input: Input): i32 throws Fault {
    if input.value < 0 {
        let payload: Box<any Show> = heap Plain(7)
        throw Fault(payload)
    }
    input.value
}
async fn propagate(read input: Input): i32 throws Fault {
    try await compute(input)
}
fn drive<F: Future<Output = (Outcome<i32, Fault>)>>(take future: F): (Outcome<i32, Fault>) {
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
    let good = Input(42)
    match take drive(propagate(read good)) {
        success(value) => { if value != 42 { return 1 } },
        failure(_) => { return 2 }
    }
    let bad = Input(-1)
    match take drive(propagate(read bad)) {
        success(_) => 3,
        failure(error) => if error.payload.value() == 7 { 0 } else { 4 }
    }
}
