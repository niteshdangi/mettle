
fn main() {
    let relaxed = core::sync::atomic::Ordering::Relaxed
    let sequential = core::sync::atomic::Ordering::SeqCst
    var first = 41
    var second = 42
    let one = core::ptr::from_mut(first)
    let two = core::ptr::from_mut(second)
    let pointer = core::sync::atomic::AtomicPtr::<i32>::new(one)
    let old = pointer.fetch_ptr_add(0,relaxed)
    let previous = pointer.swap(two,sequential)
    let actual = pointer.load(sequential)
    unsafe {
        core::intrinsics::atomic_store(one,42,sequential)
        let value = core::intrinsics::atomic_load(one,sequential)
        if old == one && previous == one && actual == two && value == 42 { 0 } else { 1 }
    }
}
