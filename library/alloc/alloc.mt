// Allocation contracts. `Global` forwards to the three `mettle_rt_*` symbols:
// hosted builds link them from the Mettle runtime, freestanding builds provide
// them. Sizes passed to them are never zero.
extern "C" {
    unsafe fn mettle_rt_alloc(size: usize, align: usize): ptr<mut u8>;
    unsafe fn mettle_rt_dealloc(p: ptr<mut u8>, size: usize, align: usize): Unit;
    unsafe fn mettle_rt_realloc(p: ptr<mut u8>, old_size: usize, align: usize, new_size: usize): ptr<mut u8>;
}

// Allocation failure: the layout that could not be satisfied.
pub copy type AllocError { pub size: usize; pub align: usize }

pub copy type LayoutError { pub size: usize; pub align: usize }

pub type PushError<T> {
    pub value: T
    pub allocation: AllocError
}

// Size and alignment of a block. `align` is a power of two and `size`
// rounded up to `align` does not exceed `isize.MAX`.
pub copy type Layout {
    size: usize
    align: usize
}

fn is_power_of_two(x: usize): bool { x != 0usize && (x & (x - 1usize)) == 0usize }

pub fn layout_from_size_align(size: usize, align: usize): Layout throws LayoutError {
    if !is_power_of_two(align) { throw LayoutError(size, align) }
    let max = 0x7fffffffffffffffusize - (align - 1usize)
    if size > max { throw LayoutError(size, align) }
    Layout(size, align)
}

// Safety: as for `layout_from_size_align`.
pub unsafe const fn layout_unchecked(size: usize, align: usize): Layout { Layout(size, align) }

pub fn layout_of<T>(): Layout {
    Layout(core.mem.size_of<T>(), core.mem.align_of<T>())
}

// Safety: `value` is a valid unsized object whose metadata describes its
// complete layout.
pub fn layout_of_val<T: unsized>(read value: T): Layout {
    let size = core.mem.size_of_val<T>(value)
    let align = core.mem.align_of_val<T>(value)
    unsafe { layout_unchecked(size, align) }
}

// Layout of `count` contiguous values of `T`.
pub fn layout_array<T>(count: usize): Layout throws LayoutError {
    let each = core.mem.size_of<T>()
    let align = core.mem.align_of<T>()
    match each.checked_mul(count) {
        present(size) => try layout_from_size_align(size, align),
        none => throw LayoutError(0usize, align)
    }
}

fn padded_size(size: usize, align: usize): usize throws LayoutError {
    let remainder = size & (align - 1usize)
    if remainder == 0usize { return size }
    match size.checked_add(align - remainder) {
        present(padded) => padded,
        none => throw LayoutError(0usize, align)
    }
}

// Places `suffix` after `prefix`, returning the combined allocation layout
// and the aligned byte offset of the suffix.
pub fn extend_layout(prefix: Layout, suffix: Layout): (Layout, usize) throws LayoutError {
    let offset = try padded_size(prefix.size, suffix.align)
    let end = match offset.checked_add(suffix.size) {
        present(size) => size,
        none => throw LayoutError(
            0usize,
            if prefix.align > suffix.align { prefix.align } else { suffix.align }
        )
    }
    let alignment = if prefix.align > suffix.align { prefix.align } else { suffix.align }
    (try layout_from_size_align(end, alignment), offset)
}

fn resized_layout(old: Layout, new_size: usize): Layout throws AllocError {
    let result = capture layout_from_size_align(new_size, old.align)
    match take result {
        success(layout) => layout,
        failure(error) => throw AllocError(error.size, error.align)
    }
}

extend Layout {
    pub fn size(): usize { self.size }
    pub fn align(): usize { self.align }
    pub fn pad_to_align(): Layout {
        let mask = self.align - 1usize
        Layout((self.size + mask) & !mask, self.align)
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

// Dangling, well-aligned address used for zero-sized blocks; never dereferenced.
const fn dangling(align: usize): ptr<mut u8> { unsafe { core.mem.transmute<ptr<mut u8>>(align) } }

// Well-aligned non-null placeholder for empty storage of `T`; never dereferenced.
pub const fn dangling_for<T>(): ptr<mut T> { dangling(core.mem.align_of<T>()).cast<T>() }

// The process-wide allocator. Stateless and freely copyable.
pub copy type Global {}

extend Global implements core.clone.Clone { fn clone(): Global { Global() } }
extend Global implements core.default.Default { static fn default(): Global { Global() } }

unsafe extend Global implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        if layout.size == 0usize { return dangling(layout.align) }
        let p = unsafe { mettle_rt_alloc(layout.size, layout.align) }
        if p == core.ptr.null_mut<u8>() { throw AllocError(layout.size, layout.align) }
        p
    }
    mut unsafe fn deallocate(p: ptr<mut u8>, layout: Layout): Unit {
        if layout.size != 0usize { unsafe { mettle_rt_dealloc(p, layout.size, layout.align) } }
    }
    mut unsafe fn grow(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        let new_layout = try resized_layout(old, new_size)
        if old.size == 0usize {
            return try self.allocate(new_layout)
        }
        if new_size == 0usize {
            self.deallocate(p, old)
            return dangling(old.align)
        }
        let q = unsafe { mettle_rt_realloc(p, old.size, old.align, new_layout.size) }
        if q == core.ptr.null_mut<u8>() { throw AllocError(new_size, old.align) }
        q
    }
    mut unsafe fn shrink(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        let new_layout = try resized_layout(old, new_size)
        if new_size == 0usize {
            if old.size != 0usize { self.deallocate(p, old) }
            return dangling(old.align)
        }
        if old.size == 0usize {
            throw AllocError(new_size, old.align)
        }
        let q = unsafe { mettle_rt_realloc(p, old.size, old.align, new_layout.size) }
        if q == core.ptr.null_mut<u8>() { throw AllocError(new_size, old.align) }
        q
    }
}

// Scope guard that returns a block to its allocator when dropped. Declared
// before other guards in a destructor so it runs last, even while unwinding.
pub type FreeBlock<A: Allocator> {
    p: ptr<mut u8>
    layout: Layout
    a: ptr<mut A>
    drop {
        if self.layout.size != 0usize { unsafe { (*self.a).deallocate(self.p, self.layout) } }
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
