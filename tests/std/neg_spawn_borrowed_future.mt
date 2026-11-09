// expect-error: type
import core.future.{Context, Future, Poll}
import std.task

type Borrowed<region r> { value: read i32 from r }
extend<region r> Borrowed<region r> implements Future {
    type Output = Unit
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<Unit> {
        let me = unsafe { self.get_unchecked_mut() }
        let value = *me.value
        Poll.Ready(())
    }
}

fn main(): i32 {
    let value = 5
    let executor = task.executor()
    executor.spawn(Borrowed(read value))
    0
}
