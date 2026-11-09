import core.future.{Future, Poll, Context, noop_waker}

async fn compute(value: i32): i32 throws i32 {
    if value < 0 { throw 7 }
    if value == 0 { return 42 }
    value + 1
}

async fn outcome_value(): (Outcome<i32, i32>) { failure(9) }

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
    let good = drive(compute(0))
    let failed = drive(compute(-1))
    let continued = drive(compute(10))
    let make = async fn(value: i32): i32 throws i32 {
        if value == 0 { throw 8 }
        value
    }
    let closure_result = drive(make(0))
    let ordinary_outcome = drive(outcome_value())
    let a = match take good { success(value) => value, failure(_) => 0 }
    let b = match take failed { success(_) => 0, failure(error) => error }
    let c = match take continued { success(value) => value, failure(_) => 0 }
    let d = match take closure_result { success(_) => 0, failure(error) => error }
    let e = match take ordinary_outcome { success(_) => 0, failure(error) => error }
    if a == 42 && b == 7 && c == 11 && d == 8 && e == 9 { 0 } else { 1 }
}
