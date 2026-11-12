fn check(order: core.sync.atomic.Ordering): bool {
    let relaxed = core.sync.atomic.Ordering.Relaxed
    let flag = core.sync.atomic.AtomicBool.new(false)
    if flag.fetch_not(order) || !flag.load(relaxed) { return false }
    if unsafe { flag.as_ptr().cast<u8>().`read`() } != 1u8 { return false }
    if !flag.fetch_not(order) || flag.load(relaxed) { return false }
    if unsafe { flag.as_ptr().cast<u8>().`read`() } != 0u8 { return false }

    var storage = 42i32
    let base = core.ptr.from_mut(storage)
    let pointer = core.sync.atomic.AtomicPtr<i32>.new(base)
    if pointer.fetch_or(3, order) != base { return false }
    let tagged = pointer.load(relaxed)
    if tagged.addr() != (base.addr() | 3usize) { return false }
    if pointer.fetch_and(!3usize, order) != tagged { return false }
    if pointer.load(relaxed) != base { return false }
    if pointer.fetch_xor(3, order) != base { return false }
    if pointer.load(relaxed) != tagged { return false }
    if pointer.fetch_xor(3usize, order) != tagged { return false }
    let restored = pointer.load(relaxed)
    if unsafe { restored.`read`() } != 42 { return false }

    if pointer.fetch_and(!0usize, order) != base ||
       pointer.fetch_or(0, order) != base ||
       pointer.fetch_xor(0, order) != base { return false }
    if pointer.fetch_xor(!0usize, order) != base { return false }
    let inverted = pointer.load(relaxed)
    if inverted.addr() != !base.addr() { return false }
    if pointer.fetch_xor(!0usize, order) != inverted { return false }
    let restored_again = pointer.load(relaxed)
    if unsafe { restored_again.`read`() } != 42 { return false }

    let null = core.ptr.null_mut<i32>()
    let empty = core.sync.atomic.AtomicPtr<i32>.new(null)
    if empty.fetch_or(3, order) != null ||
       empty.fetch_and(0, order).addr() != 3usize ||
       empty.fetch_xor(0, order) != null { return false }
    empty.load(relaxed).is_null()
}

fn main(): i32 {
    for order in [core.sync.atomic.Ordering.Relaxed,
                  core.sync.atomic.Ordering.Acquire,
                  core.sync.atomic.Ordering.Release,
                  core.sync.atomic.Ordering.AcqRel,
                  core.sync.atomic.Ordering.SeqCst] {
        if !check(order) { return 1 }
    }
    0
}
