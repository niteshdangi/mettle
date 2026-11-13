// profiles: debug release
import alloc.boxed
import core.default.Default
import core.future.{Context, Future, Poll, noop_waker}
import core.ops.Deref

type Ready { value: i32 }

extend Ready implements Future {
    type Output = i32

    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> {
        Poll.Ready(unsafe { self.get_unchecked_mut() }.value)
    }
}

fn main(): i32 {
    let empty: boxed.Pinned<i32> = boxed.Pinned<i32>.(Default).default()
    if *empty.deref() != 0 { return 1 }
    let text = boxed.Pinned<core.text.Text>.(Default).default()
    if text.deref().len() != 0usize { return 2 }
    let adopted = boxed.Pinned<i32>.(core.convert.From<boxed.Box<i32>>).from(boxed.new(11))
    if *adopted.deref() != 11 { return 5 }
    let waker = noop_waker()
    var context = Context.from_waker(read waker)
    var task = boxed.pin(Ready(9))
    var view = unsafe { core.pin.Pin.new_unchecked(mut task) }
    match view.poll(mut context) {
        Poll.Ready(value) => { if value != 9 { return 3 } },
        Poll.Pending => { return 4 }
    }
    0
}
