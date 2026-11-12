// profiles: debug release
// expect-error: region 7:42 view region or invariant payload does not satisfy its declared relationship
// expect-error-count: 1
import core.pin
fn main(): i32 {
    var value = 7i32
    let handle = core.pin.Pin.static_mut(mut value)
    *handle.get_ref()
}
