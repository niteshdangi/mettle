type PointerState {
    value: core.sync.atomic.AtomicPtr<i32>
    base: ptr<mut i32>
}

extern "C" {
    unsafe fn mettle_atomic_bitwise_contention(
        reset: unsafe extern "C" fn(ptr<mut Unit>, u32): Unit,
        modify: unsafe extern "C" fn(ptr<mut Unit>, u32, u32): usize,
        load: unsafe extern "C" fn(ptr<mut Unit>, u32): usize,
        context: ptr<mut Unit>, base: usize, operation: u32): i32;
}

unsafe extern "C" fn reset_bool(context: ptr<mut Unit>, operation: u32) {
    let flag = read *context.cast<core.sync.atomic.AtomicBool>()
    flag.store(false, core.sync.atomic.Ordering.Relaxed)
}

unsafe extern "C" fn flip(context: ptr<mut Unit>, operation: u32, worker: u32): usize {
    let flag = read *context.cast<core.sync.atomic.AtomicBool>()
    if flag.fetch_not(core.sync.atomic.Ordering.Relaxed) { 1usize } else { 0usize }
}

unsafe extern "C" fn load_bool(context: ptr<mut Unit>, operation: u32): usize {
    let flag = read *context.cast<core.sync.atomic.AtomicBool>()
    if flag.load(core.sync.atomic.Ordering.Relaxed) { 1usize } else { 0usize }
}

unsafe extern "C" fn reset_pointer(context: ptr<mut Unit>, operation: u32) {
    let state = read *context.cast<PointerState>()
    let initial = if operation == 2u32 {
        state.base.with_addr(state.base.addr() | 3usize)
    } else { state.base }
    state.value.store(initial, core.sync.atomic.Ordering.Relaxed)
}

unsafe extern "C" fn mask_pointer(
    context: ptr<mut Unit>, operation: u32, worker: u32): usize {
    let state = read *context.cast<PointerState>()
    let bit = 1usize << worker
    let order = core.sync.atomic.Ordering.Relaxed
    let old = if operation == 1u32 { state.value.fetch_or(bit, order) }
              else if operation == 2u32 { state.value.fetch_and(!bit, order) }
              else { state.value.fetch_xor(bit, order) }
    old.addr()
}

unsafe extern "C" fn load_pointer(context: ptr<mut Unit>, operation: u32): usize {
    let state = read *context.cast<PointerState>()
    state.value.load(core.sync.atomic.Ordering.Relaxed).addr()
}

fn main(): i32 {
    let flag = core.sync.atomic.AtomicBool.new(false)
    let flag_context = core.ptr.from_ref(flag).cast_mut().cast<Unit>()
    if unsafe {
        mettle_atomic_bitwise_contention(
            reset_bool, flip, load_bool, flag_context, 0usize, 0u32)
    } != 0 { return 1 }

    var storage = 42i32
    let base = core.ptr.from_mut(storage)
    let state = PointerState(core.sync.atomic.AtomicPtr<i32>.new(base), base)
    let context = core.ptr.from_ref(state).cast_mut().cast<Unit>()
    for operation in [1u32, 2u32, 3u32] {
        if unsafe {
            mettle_atomic_bitwise_contention(
                reset_pointer, mask_pointer, load_pointer,
                context, base.addr(), operation)
        } != 0 { return 2 }
    }
    let relaxed = core.sync.atomic.Ordering.Relaxed
    let _ = state.value.fetch_and(!3usize, relaxed)
    let restored = state.value.load(relaxed)
    if restored != base { return 3 }
    if unsafe { restored.`read`() } == 42 { 0 } else { 4 }
}
