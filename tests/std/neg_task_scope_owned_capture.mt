// expect-error: region 19:21 viewed source does not outlive the required region
import core.future.{Context, Future, Poll}
import std.task

type Owner { value: i32 }
type Child<region r> { owner: read Owner from r }
extend<region r> Child<region r> implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        Poll.Ready(me.owner.value)
    }
}
fn main(): i32 {
    let owner = heap Owner(3)
    let token = heap 7
    task.scope(take fn(read s: task.Scope): Unit {
        let consumed = token.into_inner()
        let child = s.spawn(Child(owner.get()))
        core.mem.forget(child)
    })
    0
}
