// profiles: debug release
// expect-error: constant 9:29 constant result cannot retain a pointer or view of local storage
// expect-error-count: 1
import core.ptr.NonNull
const fn escaping(): NonNull<i32> {
    let value = 7i32
    NonNull.from_ref(read value)
}
static LEAK: NonNull<i32> = escaping()
fn main(): i32 { 0 }
