// profiles: debug release
// expect-error-source: core/ptr.mt
// expect-error: constant 79:18 constant mut view requires writable provenance
// expect-error-count: 1
import core.ptr.NonNull
const fn forbidden_write(): i32 {
    let value = 7i32
    var pointer = NonNull.from_ref(read value)
    unsafe { *pointer.as_mut() = 9i32 }
    0i32
}
const VALUE: i32 = forbidden_write()
fn main(): i32 { VALUE }
