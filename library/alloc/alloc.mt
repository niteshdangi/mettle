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

// Size and alignment of a block. `align` is a power of two and `size`
// rounded up to `align` does not exceed `isize::MAX`.
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
pub unsafe fn layout_unchecked(size: usize, align: usize): Layout { Layout(size, align) }

pub fn layout_of<T>(): Layout {
    Layout(core::mem::size_of::<T>(), core::mem::align_of::<T>())
}

// Layout of `count` contiguous values of `T`.
pub fn layout_array<T>(count: usize): Layout throws LayoutError {
    let each = core::mem::size_of::<T>()
    let align = core::mem::align_of::<T>()
    match each.checked_mul(count) {
        present(size) => try layout_from_size_align(size, align),
        none => throw LayoutError(0usize, align)
    }
}

impl Layout {
    pub fn size(): usize { self.size }
    pub fn align(): usize { self.align }
}

// Allocator contract. A block must be returned to the allocator value that
// produced it (or one that is documented to be compatible) with the layout it
// was allocated with. `grow`/`shrink` keep the original block valid on failure.
pub interface Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError;
    mut fn deallocate(p: ptr<mut u8>, layout: Layout): Unit;
    mut fn grow(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError;
    mut fn shrink(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError;
}

// Dangling, well-aligned address used for zero-sized blocks; never dereferenced.
fn dangling(align: usize): ptr<mut u8> { unsafe { core::mem::transmute::<ptr<mut u8>>(align) } }

// Well-aligned non-null placeholder for empty storage of `T`; never dereferenced.
pub fn dangling_for<T>(): ptr<mut T> { dangling(core::mem::align_of::<T>()).cast::<T>() }

// The process-wide allocator. Stateless and freely copyable.
pub copy type Global {}

impl Global implements package::core::clone::Clone { fn clone(): Global { Global() } }
impl Global implements package::core::default::Default { static fn default(): Global { Global() } }

impl Global implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        if layout.size == 0usize { return dangling(layout.align) }
        let p = unsafe { mettle_rt_alloc(layout.size, layout.align) }
        if p == core::ptr::null_mut::<u8>() { throw AllocError(layout.size, layout.align) }
        p
    }
    mut fn deallocate(p: ptr<mut u8>, layout: Layout): Unit {
        if layout.size != 0usize { unsafe { mettle_rt_dealloc(p, layout.size, layout.align) } }
    }
    mut fn grow(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        if old.size == 0usize {
            return try self.allocate(Layout(new_size, old.align))
        }
        let q = unsafe { mettle_rt_realloc(p, old.size, old.align, new_size) }
        if q == core::ptr::null_mut::<u8>() { throw AllocError(new_size, old.align) }
        q
    }
    mut fn shrink(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        if new_size == 0usize {
            self.deallocate(p, old)
            return dangling(old.align)
        }
        let q = unsafe { mettle_rt_realloc(p, old.size, old.align, new_size) }
        if q == core::ptr::null_mut::<u8>() { throw AllocError(new_size, old.align) }
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
pub unsafe fn free_block<A: Allocator>(p: ptr<mut u8>, layout: Layout, a: ptr<mut A>): FreeBlock<A> {
    FreeBlock(p, layout, a)
}

// Terminates the process after an unrecoverable allocation failure. Ordinary
// (non-`try_`) operations route here; policy is abort, never unwinding through
// allocator callbacks.
pub fn handle_alloc_error(layout: Layout): Never {
    core::intrinsics::abort()
}

// Panic used for precondition violations (bounds, boundaries, capacity
// overflow). The out-of-range access traps through the runtime panic path,
// which runs cleanup; `abort` is only reached if the trap were optimized away.
pub fn panic_precondition(): Never {
    let empty: [u8; 1] = [0u8]
    let one = 1usize
    let at = unsafe { core::ptr::`read_volatile`(core::ptr::from_ref(one)) }
    let _unused = empty[at]
    core::intrinsics::abort()
}
