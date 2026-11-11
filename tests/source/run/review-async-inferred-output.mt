import core.future.{Future, Poll, Context, noop_waker}
async fn answer() { 7i32 }
fn drive<F: Future<Output = i32>>(take future: F): i32 {
    let waker = noop_waker()
    var slot = core.pin.pin(future)
    loop {
        var context = Context.from_waker(read waker)
        match take slot.as_mut().poll(mut context) {
            Poll.Ready(value) => { return value },
            Poll.Pending => {}
        }
    }
}
fn main(): i32 { drive(answer()) - 7 }
