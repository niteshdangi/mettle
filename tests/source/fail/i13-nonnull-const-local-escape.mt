// profiles: debug release
// expect-error: constant 11:21 constant result cannot retain a pointer or view of local storage
// expect-error-count: 1
import core.ptr.NonNull
type Leak { pointer: NonNull<i32> }
unsafe extend Leak implements Shareable {}
const fn escaping(): Leak {
    let value = 7i32
    Leak(NonNull.from_ref(read value))
}
static LEAK: Leak = escaping()
fn main(): i32 { 0 }
