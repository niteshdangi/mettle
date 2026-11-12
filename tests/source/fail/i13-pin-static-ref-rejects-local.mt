// profiles: debug release
// expect-error: region 7:18 view region or invariant payload does not satisfy its declared relationship
// expect-error-count: 1
import core.pin
fn main(): i32 {
    let value = 7i32
    let handle = core.pin.Pin.static_ref(read value)
    *handle.get_ref()
}
