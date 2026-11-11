import core.future.{Future, Poll, Context, noop_waker}

// Awaits compose with every statement form: borrows of body locals live across
// suspensions, awaits sit in lazy operands, loop values and branches that
// return or throw, and an unfinished future drops exactly its live locals.

type YieldOnce { value: i32; yielded: bool }
extend YieldOnce implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.yielded { Poll.Ready(me.value) } else {
            me.yielded = true
            cx.waker().wake_by_ref()
            Poll.Pending
        }
    }
}
fn later(value: i32): YieldOnce { YieldOnce(value, false) }

macro identity { ($value:expr) => { $value }; }
macro await_plus_one { () => { await later(2) + 1 }; }
async fn macro_await(): i32 { identity!(await later(4)) + 2 * await_plus_one!() }

type Guard {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter = *self.counter + 1 } }
}

async fn borrow_across(): i32 {
    let value = 5
    let view = read value
    let n = await later(1)
    *view + n
}

async fn borrow_in_loop(): i32 {
    let value = 2
    let view = read value
    var total = 0
    while total < 6 { total = total + *view + await later(0) }
    total
}

async fn early_return(c: bool): i32 {
    var n = 0
    if c {
        n = await later(7)
        return n
    }
    n + 1
}

async fn lazy_operand(x: bool): bool { x && await later(1) == 1 }

async fn throw_in_loop(): i32 throws i32 {
    var total = 0
    while total < 3 {
        if total == 2 { throw 40 }
        total = total + await later(1)
    }
    total
}

async fn loop_value(): i32 {
    let n = loop { break await later(9) }
    n
}

fn positive(value: i32): i32 throws i32 { if value > 0 { value } else { throw value } }
async fn rethrow(value: i32): i32 throws i32 { try positive(await later(value)) + 1 }

async fn hold(counter: ptr<mut i32>): i32 {
    let first = Guard(counter)
    let n = await later(3)
    let second = Guard(counter)
    n + await later(4)
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

fn poll_times<F: Future>(take future: F, times: i32): Unit {
    let waker = noop_waker()
    var slot = core.pin.pin(future)
    var left = times
    while left > 0 {
        var cx = Context.from_waker(read waker)
        let _ = slot.as_mut().poll(mut cx)
        left = left - 1
    }
}

fn main(): i32 {
    if drive(macro_await()) != 10 { return 8 }
    if drive(borrow_across()) != 6 { return 1 }
    if drive(borrow_in_loop()) != 6 { return 2 }
    if drive(early_return(true)) != 7 || drive(early_return(false)) != 1 { return 3 }
    if !drive(lazy_operand(true)) || drive(lazy_operand(false)) { return 4 }
    match take drive(throw_in_loop()) { success(_) => { return 5 }, failure(error) => if error != 40 { return 5 } }
    if drive(loop_value()) != 9 { return 6 }
    match take drive(rethrow(-2)) { success(_) => { return 7 }, failure(error) => if error != -2 { return 7 } }
    match take drive(rethrow(2)) { success(value) => if value != 3 { return 7 }, failure(_) => { return 7 } }
    var drops = 0
    let counter = core.ptr.from_mut(mut drops)
    poll_times(hold(counter), 0)
    if drops != 0 { return 8 }
    poll_times(hold(counter), 1)
    if drops != 1 { return 9 }
    poll_times(hold(counter), 2)
    if drops != 3 { return 10 }
    if drive(hold(counter)) != 7 || drops != 5 { return 11 }
    0
}
