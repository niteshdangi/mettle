// profiles: debug release
// expect-error: ownership 10:17 moved
// expect-error-count: 1
import core.pin
static mut VALUE: i32 = 7i32
fn main(): i32 {
    let view: mut i32 from static = unsafe { mut VALUE }
    let handle = core.pin.Pin.static_mut(take view)
    let observed = *handle.get_ref()
    observed + *view
}
