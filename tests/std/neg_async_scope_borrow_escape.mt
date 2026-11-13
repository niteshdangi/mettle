// expect-error: ownership 21:5 access or storage conflicts with a live read loan
import core.future.{Context, Future, Poll}
import std.task

type Borrowed<region r> { value: read i32 from r }
extend<region r> Borrowed<region r> implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        Poll.Ready(*me.value)
    }
}

fn main(): i32 {
    let anchor = 1
    var scope = task.async_scope(read anchor)
    {
        let short = 2
        let child = scope.spawn(Borrowed(read short))
        core.mem.forget(take child)
    }
    0
}
