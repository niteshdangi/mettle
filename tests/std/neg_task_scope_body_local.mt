// expect-error: region
import core.future.{Context, Future, Poll};
import std.task;

type Child<region r> { value: read i32 from r }
extend<region r> Child<region r> implements Future {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        Poll.Ready(*me.value)
    }
}

fn main(): i32 {
    task.scope(fn(s: read task.Scope): Unit {
        let inner = 3
        let child = s.spawn(Child(read inner))
        core.mem.forget(take child)
    })
    0
}
