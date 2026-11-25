// Allocation-independent size, alignment and provider-interface contracts.
import super.ptr.NonNull
import super.fmt.{Debug, Display, Error, Formatter}

pub copy type LayoutError { pub size: usize; pub align: usize }
pub alias LayoutErr = LayoutError;
extend LayoutError implements super.clone.Clone {
    fn clone(): LayoutError { LayoutError(self.size, self.align) }
}
extend LayoutError implements super.cmp.PartialEq {
    fn eq(read other: LayoutError): bool { self.size == other.size && self.align == other.align }
}
extend LayoutError implements super.cmp.Eq {}
extend LayoutError implements super.error.Error {}

extend LayoutError implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("LayoutError")
        try debug.field("size", self.size)
        try debug.field("align", self.align)
        try debug.finish()
    }
}
extend LayoutError implements Display {
    fn fmt(mut f: Formatter): Unit throws Error { try f.write_str("invalid layout") }
}

// Size and alignment of a block. `align` is a power of two and `size`
// rounded up to `align` does not exceed `isize.MAX`.
pub copy type Layout {
    size: usize
    align: usize
}
extend Layout implements super.clone.Clone {
    fn clone(): Layout { Layout(self.size, self.align) }
}
extend Layout implements super.cmp.PartialEq {
    fn eq(read other: Layout): bool { self.size == other.size && self.align == other.align }
}
extend Layout implements super.cmp.Eq {}
extend Layout implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Layout")
        try debug.field("size", self.size)
        try debug.field("align", self.align)
        try debug.finish()
    }
}
extend Layout implements super.hash.Hash {
    fn hash<H: super.hash.Hasher>(mut state: H): Unit {
        state.write_usize(self.size)
        state.write_usize(self.align)
    }
}

fn is_power_of_two(x: usize): bool { x != 0usize && (x & (x - 1usize)) == 0usize }

pub const fn layout_from_size_align(size: usize, align: usize): Layout throws LayoutError {
    if !is_power_of_two(align) { throw LayoutError(size, align) }
    let max = (isize.MAX as usize) - (align - 1usize)
    if size > max { throw LayoutError(size, align) }
    Layout(size, align)
}

// Safety: as for `layout_from_size_align`.
pub unsafe const fn layout_unchecked(size: usize, align: usize): Layout { Layout(size, align) }

pub const fn layout_of<T>(): Layout {
    Layout(core.mem.size_of<T>(), core.mem.align_of<T>())
}

// Safety: `value` is a valid unsized object whose metadata describes its
// complete layout.
pub const fn layout_of_val<T: unsized>(read value: T): Layout {
    let size = core.mem.size_of_val<T>(value)
    let align = core.mem.align_of_val<T>(value)
    unsafe { layout_unchecked(size, align) }
}

// Layout of `count` contiguous values of `T`.
pub const fn layout_array<T>(count: usize): Layout throws LayoutError {
    let each = core.mem.size_of<T>()
    let align = core.mem.align_of<T>()
    match each.checked_mul(count) {
        present(size) => try layout_from_size_align(size, align),
        none => throw LayoutError(0usize, align)
    }
}

const fn padded_size(size: usize, align: usize): usize throws LayoutError {
    let remainder = size & (align - 1usize)
    if remainder == 0usize { return size }
    match size.checked_add(align - remainder) {
        present(padded) => padded,
        none => throw LayoutError(0usize, align)
    }
}

// Places `suffix` after `prefix`, returning the combined allocation layout
// and the aligned byte offset of the suffix.
pub const fn extend_layout(prefix: Layout, suffix: Layout): (Layout, usize) throws LayoutError {
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

extend Layout {
    pub static const fn new<T>(): Layout { layout_of<T>() }
    pub static const fn from_size_align(size: usize, align: usize): Layout throws LayoutError {
        try layout_from_size_align(size, align)
    }

    // Safety: size and align must satisfy the Layout invariants.
    pub static unsafe const fn from_size_align_unchecked(size: usize, align: usize): Layout {
        unsafe { layout_unchecked(size, align) }
    }

    pub static const fn for_value<T: unsized>(read value: T): Layout {
        layout_of_val(value)
    }

    // Safety: the pointee's metadata is valid and its dynamic layout fits isize.
    pub static unsafe const fn for_value_raw<T: unsized>(pointer: ptr<read T>): Layout {
        let size = unsafe { core.mem.size_of_val_raw<T>(pointer) }
        let align = unsafe { core.mem.align_of_val_raw<T>(pointer) }
        unsafe { layout_unchecked(size, align) }
    }

    pub static const fn array<T>(count: usize): Layout throws LayoutError {
        try layout_array<T>(count)
    }

    pub const fn size(): usize { self.size }
    pub const fn align(): usize { self.align }

    pub const fn extend(next: Layout): (Layout, usize) throws LayoutError {
        try extend_layout(self, next)
    }

    pub const fn align_to(align: usize): Layout throws LayoutError {
        if !is_power_of_two(align) { throw LayoutError(self.size, align) }
        let alignment = if self.align > align { self.align } else { align }
        try layout_from_size_align(self.size, alignment)
    }

    pub const fn pad_to_align(): Layout {
        let mask = self.align - 1usize
        Layout((self.size + mask) & !mask, self.align)
    }

    pub const fn extend_packed(next: Layout): Layout throws LayoutError {
        let size = match self.size.checked_add(next.size) {
            present(size) => size,
            none => throw LayoutError(0usize, self.align)
        }
        try layout_from_size_align(size, self.align)
    }

    pub const fn repeat(count: usize): (Layout, usize) throws LayoutError {
        let stride = self.pad_to_align().size
        let size = if count == 0usize {
            0usize
        } else {
            let repeated = match stride.checked_mul(count - 1usize) {
                present(size) => size,
                none => throw LayoutError(0usize, self.align)
            }
            match repeated.checked_add(self.size) {
                present(size) => size,
                none => throw LayoutError(0usize, self.align)
            }
        }
        (try layout_from_size_align(size, self.align), stride)
    }

    pub const fn repeat_packed(count: usize): Layout throws LayoutError {
        let size = match self.size.checked_mul(count) {
            present(size) => size,
            none => throw LayoutError(0usize, self.align)
        }
        try layout_from_size_align(size, self.align)
    }

    pub const fn dangling_ptr(): NonNull<u8> {
        unsafe { NonNull<u8>.new_unchecked(core.ptr.without_provenance_mut<u8>(self.align)) }
    }
}

// Well-aligned non-null placeholder for empty storage of `T`; never dereferenced.
pub const fn dangling_for<T>(): ptr<mut T> {
    core.ptr.without_provenance_mut<T>(core.mem.align_of<T>())
}

// Safety: implementations uphold allocation validity, exclusivity and no-unwind guarantees.
pub unsafe interface GlobalAlloc {
    // Safety: layout is valid and nonzero; the returned block is live and exclusive.
    unsafe fn alloc(layout: Layout): ptr<mut u8>;

    // Safety: pointer is a live block from this allocator with exactly this layout.
    unsafe fn dealloc(pointer: ptr<mut u8>, layout: Layout): Unit;

    // Safety: as for alloc; zeroed bytes need not represent a valid typed value.
    unsafe fn alloc_zeroed(layout: Layout): ptr<mut u8> {
        let pointer = unsafe { self.alloc(layout) }
        if pointer != core.ptr.null_mut<u8>() {
            unsafe { pointer.write_bytes(0u8, layout.size()) }
        }
        pointer
    }

    // Safety: pointer and layout identify a live block; new_size is nonzero and valid.
    unsafe fn realloc(
        pointer: ptr<mut u8>,
        layout: Layout,
        new_size: usize
    ): ptr<mut u8> {
        let new_layout = unsafe { layout_unchecked(new_size, layout.align()) }
        let replacement = unsafe { self.alloc(new_layout) }
        if replacement == core.ptr.null_mut<u8>() { return replacement }
        let count = if layout.size() < new_size { layout.size() } else { new_size }
        unsafe { core.ptr.copy_nonoverlapping(pointer.cast_const(), replacement, count) }
        unsafe { self.dealloc(pointer, layout) }
        replacement
    }
}
