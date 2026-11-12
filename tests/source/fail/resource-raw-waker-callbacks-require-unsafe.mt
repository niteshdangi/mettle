// expect-error: unsafe 13:5 requires an unsafe block
// expect-error: unsafe 14:5 requires an unsafe block
// expect-error: unsafe 15:5 requires an unsafe block
// expect-error: unsafe 16:5 requires an unsafe block
// expect-error-count: 4
import core.future.Waker
fn main(): i32 {
    let waker = Waker.noop()
    let release = waker.vtable().release
    let wake = waker.vtable().wake
    let wake_by_ref = waker.vtable().wake_by_ref
    let clone = waker.vtable().clone
    release(waker.data())
    wake(waker.data())
    wake_by_ref(waker.data())
    clone(waker.data())
    0
}
