
fn main() {
    let relaxed = core::sync::atomic::Ordering::Relaxed
    let acquire = core::sync::atomic::Ordering::Acquire
    let release = core::sync::atomic::Ordering::Release
    let sequential = core::sync::atomic::Ordering::SeqCst
    let value = core::sync::atomic::AtomicI32::new(40)
    let previous = value.fetch_add(2,sequential)
    let success_value = match value.compare_exchange(42,43,release,acquire) {
        success(old) => old, failure(old) => -100
    }
    let failure_value = match value.compare_exchange(0,1,relaxed,sequential) {
        success(old) => -100, failure(old) => old
    }
    var flag = core::sync::atomic::AtomicBool::new(true)
    let address = flag.as_ptr()
    let mutable = flag.get_mut()
    *mutable = false
    let changed = match flag.compare_exchange(false,true,sequential,acquire) {
        success(old) => !old, failure(old) => false
    }
    let old_flag = flag.fetch_nand(true,sequential)
    let bits = unsafe { address.cast::<u8>().`read`() }
    core::sync::atomic::fence(acquire)
    core::sync::atomic::compiler_fence(release)
    if previous == 40 && success_value == 42 && failure_value == 43 &&
       value.load(acquire) == 43 && changed && old_flag &&
       !flag.load(relaxed) && bits == 0u8 { 0 } else { 1 }
}
