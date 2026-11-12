// expect-error: type 10:29 expected usize
// expect-error: type 11:28 expected usize
// expect-error: type 12:29 expected usize
// expect-error: type 14:13 invalid primitive operation or operand types
fn main() {
    let order = core.sync.atomic.Ordering.Relaxed
    var storage = 42i32
    let address = core.ptr.from_mut(storage)
    let value = core.sync.atomic.AtomicPtr<i32>.new(address)
    let _ = value.fetch_and(address, order)
    let _ = value.fetch_or(address, order)
    let _ = value.fetch_xor(address, order)
    let integer = core.sync.atomic.AtomicI32.new(0)
    let _ = integer.fetch_not(order)
    0
}
