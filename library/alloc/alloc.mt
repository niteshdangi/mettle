import super.collections.TryReserveError

// Allocation contracts. `Global` forwards to the three `mettle_rt_*` symbols:
// hosted builds link them from the Mettle runtime, freestanding builds provide
// them. Sizes passed to them are never zero.
pub import core.alloc.{
    GlobalAlloc,
    Layout,
    LayoutErr,
    LayoutError,
    dangling_for,
    extend_layout,
    layout_array,
    layout_from_size_align,
    layout_of,
    layout_of_val,
    layout_unchecked
}

extern "C" {
    unsafe fn mettle_rt_alloc(size: usize, align: usize): ptr<mut u8>;
    unsafe fn mettle_rt_dealloc(p: ptr<mut u8>, size: usize, align: usize): Unit;
    unsafe fn mettle_rt_realloc(p: ptr<mut u8>, old_size: usize, align: usize, new_size: usize): ptr<mut u8>;
}

// Allocation failure: the layout that could not be satisfied.
pub copy type AllocError { pub size: usize; pub align: usize }

pub type PushError<T> {
    pub value: T
    pub error: TryReserveError
}

fn resized_layout(old: Layout, new_size: usize): Layout throws AllocError {
    let result = capture layout_from_size_align(new_size, old.align())
    match take result {
        success(layout) => layout,
        failure(error) => throw AllocError(error.size, error.align)
    }
}

// Safety: providers return live, exclusive storage matching its layout; clones
// remain compatible; resize failure or unwind preserves the original initialized block.
pub unsafe interface Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError;
    // Safety: the block is live, exclusively owned and matches this allocator/layout.
    mut unsafe fn deallocate(p: ptr<mut u8>, layout: Layout): Unit;
    // Safety: as for deallocate; new_size >= old.size. Failure preserves the block.
    mut unsafe fn grow(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError;
    // Safety: as for deallocate; new_size <= old.size. Failure preserves the block.
    mut unsafe fn shrink(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError;
}

// The process-wide allocator. Stateless and freely copyable.
pub copy type Global {}

extend Global implements core.clone.Clone { fn clone(): Global { Global() } }
extend Global implements core.default.Default { static fn default(): Global { Global() } }

unsafe extend Global implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        if layout.size() == 0usize { return dangling_for<u8>() }
        let p = unsafe { mettle_rt_alloc(layout.size(), layout.align()) }
        if p == core.ptr.null_mut<u8>() { throw AllocError(layout.size(), layout.align()) }
        p
    }
    mut unsafe fn deallocate(p: ptr<mut u8>, layout: Layout): Unit {
        if layout.size() != 0usize { unsafe { mettle_rt_dealloc(p, layout.size(), layout.align()) } }
    }
    mut unsafe fn grow(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        let new_layout = try resized_layout(old, new_size)
        if old.size() == 0usize {
            return try self.allocate(new_layout)
        }
        if new_size == 0usize {
            self.deallocate(p, old)
            return dangling_for<u8>()
        }
        let q = unsafe { mettle_rt_realloc(p, old.size(), old.align(), new_layout.size()) }
        if q == core.ptr.null_mut<u8>() { throw AllocError(new_size, old.align()) }
        q
    }
    mut unsafe fn shrink(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        let new_layout = try resized_layout(old, new_size)
        if new_size == 0usize {
            if old.size() != 0usize { self.deallocate(p, old) }
            return dangling_for<u8>()
        }
        if old.size() == 0usize {
            throw AllocError(new_size, old.align())
        }
        let q = unsafe { mettle_rt_realloc(p, old.size(), old.align(), new_layout.size()) }
        if q == core.ptr.null_mut<u8>() { throw AllocError(new_size, old.align()) }
        q
    }
}

unsafe extend Global implements GlobalAlloc {
    unsafe fn alloc(layout: Layout): ptr<mut u8> {
        unsafe { super.alloc.alloc(layout) }
    }

    unsafe fn dealloc(pointer: ptr<mut u8>, layout: Layout): Unit {
        unsafe { super.alloc.dealloc(pointer, layout) }
    }

    unsafe fn realloc(pointer: ptr<mut u8>, layout: Layout, new_size: usize): ptr<mut u8> {
        unsafe { super.alloc.realloc(pointer, layout, new_size) }
    }
}

// Safety: layout must be valid and nonzero; use and release the returned block accordingly.
pub unsafe fn alloc(layout: Layout): ptr<mut u8> {
    var global = Global()
    match capture global.allocate(layout) {
        success(pointer) => pointer,
        failure(_) => core.ptr.null_mut<u8>()
    }
}

// Safety: layout must be valid and nonzero; release the returned block with the same layout.
pub unsafe fn alloc_zeroed(layout: Layout): ptr<mut u8> {
    let pointer = unsafe { alloc(layout) }
    if pointer != core.ptr.null_mut<u8>() {
        unsafe { pointer.write_bytes(0u8, layout.size()) }
    }
    pointer
}

// Safety: pointer must be a live Global block with exactly this nonzero layout.
pub unsafe fn dealloc(pointer: ptr<mut u8>, layout: Layout): Unit {
    var global = Global()
    unsafe { global.deallocate(pointer, layout) }
}

// Safety: pointer must be a live exclusive Global block with exactly this nonzero layout.
pub unsafe fn realloc(
    pointer: ptr<mut u8>,
    layout: Layout,
    new_size: usize
): ptr<mut u8> {
    var global = Global()
    let resized = if new_size >= layout.size() {
        unsafe { capture global.grow(pointer, layout, new_size) }
    } else {
        unsafe { capture global.shrink(pointer, layout, new_size) }
    }
    match take resized {
        success(replacement) => replacement,
        failure(_) => core.ptr.null_mut<u8>()
    }
}

// Scope guard that returns a block to its allocator when dropped. Declared
// before other guards in a destructor so it runs last, even while unwinding.
pub type FreeBlock<A: Allocator> {
    p: ptr<mut u8>
    layout: Layout
    a: ptr<mut A>
    drop {
        if self.layout.size() != 0usize { unsafe { (*self.a).deallocate(self.p, self.layout) } }
    }
}

// Safety: `a` outlives the guard and `p` is a live block of `layout` from it.
pub unsafe const fn free_block<A: Allocator>(p: ptr<mut u8>, layout: Layout, a: ptr<mut A>): FreeBlock<A> {
    FreeBlock(p, layout, a)
}

// Terminates the process after an unrecoverable allocation failure. Ordinary
// (non-`try_`) operations route here; policy is abort, never unwinding through
// allocator callbacks.
pub fn handle_alloc_error(layout: Layout): Never {
    core.intrinsics.abort()
}

// Panic used for precondition violations (bounds, boundaries, capacity
// overflow). The out-of-range access traps through the runtime panic path,
// which runs cleanup; `abort` is only reached if the trap were optimized away.
pub fn panic_precondition(): Never {
    let empty: [u8; 1] = [0u8]
    let one = 1usize
    let at = unsafe { core.ptr.`read_volatile`(core.ptr.from_ref(one)) }
    let _unused = empty[at]
    core.intrinsics.abort()
}
