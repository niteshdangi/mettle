// A raw mutable pointer that is guaranteed not to be null.
import super.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import super.convert.From
import super.fmt.{Debug, Error, Formatter, fmt_radix}
import super.hash.{Hash, Hasher}

pub copy type NonNull<T: unsized> {
    pointer: ptr<mut T>
}

// Raw slice pointer metadata is the element count following the data pointer.
copy type RawSlice<T> {
    data: ptr<mut T>
    length: usize
}

// Safety: ranges must be valid, aligned, and nonoverlapping for `count`.
pub unsafe fn copy_nonoverlapping<T>(
    source: ptr<read T>,
    destination: ptr<mut T>,
    count: usize
): Unit {
    unsafe { core.ptr.`copy`(source, destination, count) }
}

pub fn eq<T: unsized>(left: ptr<read T>, right: ptr<read T>): bool {
    left == right
}

extend<T: unsized> NonNull<T> {
    pub static fn new(pointer: ptr<mut T>): NonNull<T>? {
        if pointer.is_null() { none } else { present(NonNull(pointer)) }
    }

    pub static fn from_ref(value: read T): NonNull<T> {
        NonNull(core.ptr.from_ref(value).cast_mut())
    }

    pub static fn from_mut(mut value: T): NonNull<T> {
        NonNull(core.ptr.from_mut(mut value))
    }

    // Safety: the caller must guarantee `pointer` is non-null.
    pub unsafe static fn new_unchecked(pointer: ptr<mut T>): NonNull<T> {
        NonNull(pointer)
    }

    pub fn as_ptr(): ptr<mut T> { self.pointer }

    pub fn addr(): core.num.NonZero<usize> {
        unsafe { core.num.NonZero<usize>.new_unchecked(self.pointer.addr()) }
    }

    pub fn expose_provenance(): core.num.NonZero<usize> {
        unsafe {
            core.num.NonZero<usize>.new_unchecked(self.pointer.expose_provenance())
        }
    }

    pub fn with_addr(address: core.num.NonZero<usize>): NonNull<T> {
        NonNull(self.pointer.with_addr(address.get()))
    }

    pub fn map_addr<F: take fn(core.num.NonZero<usize>): core.num.NonZero<usize>>(
        take f: F
    ): NonNull<T> {
        self.with_addr(f(self.addr()))
    }

    pub fn cast<U>(): NonNull<U> { NonNull(self.pointer.cast<U>()) }

    // Safety: the pointer must be valid, aligned, and initialized for `T`.
    pub unsafe fn as_ref(): read T from self {
        unsafe { read *self.pointer }
    }

    // Safety: the pointer must be uniquely accessible and valid for `T`.
    pub unsafe mut fn as_mut(): mut T from self {
        unsafe { mut *self.pointer }
    }

    // Safety: the result must remain within or one past the allocated object.
    pub unsafe fn byte_add(count: usize): NonNull<T> {
        NonNull(unsafe { self.pointer.byte_add(count) })
    }

    // Safety: the result must remain within or one past the allocated object.
    pub unsafe fn byte_sub(count: usize): NonNull<T> {
        NonNull(unsafe { self.pointer.byte_sub(count) })
    }

    // Safety: the result must remain within or one past the allocated object.
    pub unsafe fn byte_offset(count: isize): NonNull<T> {
        NonNull(unsafe { self.pointer.byte_offset(count) })
    }

    // Safety: pointers must share an allocation and their byte distance fit `isize`.
    pub unsafe fn byte_offset_from(origin: NonNull<T>): isize {
        unsafe { self.pointer.byte_offset_from(origin.pointer) }
    }

    // Safety: pointers must share an allocation and `self` must follow `origin`.
    pub unsafe fn byte_offset_from_unsigned(origin: NonNull<T>): usize {
        unsafe { self.pointer.byte_offset_from_unsigned(origin.pointer) }
    }

    // Safety: the pointer must address a valid `T` whose destructor has not run.
    pub unsafe fn drop_in_place(): Unit {
        unsafe { core.ptr.drop_in_place(self.pointer) }
    }

}

extend<T: unsized> NonNull<T> implements super.clone.Clone {
    fn clone(): NonNull<T> { self }
}

extend<region r, T: unsized> NonNull<T> implements From<mut T from r> {
    static fn from(take value: mut T from r): NonNull<T> {
        NonNull(core.ptr.from_mut(value))
    }
}

extend<region r, T: unsized> NonNull<T> implements From<read T from r> {
    static fn from(take value: read T from r): NonNull<T> {
        NonNull(core.ptr.from_ref(value).cast_mut())
    }
}

extend<T: unsized> NonNull<T> implements PartialEq {
    fn eq(read other: NonNull<T>): bool { self.pointer == other.pointer }
}

extend<T: unsized> NonNull<T> implements Eq {}

extend<T: unsized> NonNull<T> implements PartialOrd {
    fn partial_cmp(read other: NonNull<T>): Ordering? {
        present(self.cmp(read other))
    }
}

extend<T: unsized> NonNull<T> implements Ord {
    fn cmp(read other: NonNull<T>): Ordering {
        if self.pointer < other.pointer { Ordering.Less }
        else if self.pointer == other.pointer { Ordering.Equal }
        else { Ordering.Greater }
    }
}

extend<T: unsized> NonNull<T> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        state.write_usize(self.pointer.addr())
    }
}

extend<T: unsized> NonNull<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try f.write_str("0x")
        try fmt_radix(mut f, self.pointer.addr() as u64, false, 16u64, false, "")
    }
}

extend<T> NonNull<T> {
    pub static fn with_exposed_provenance(
        address: core.num.NonZero<usize>
    ): NonNull<T> {
        NonNull(core.ptr.with_exposed_provenance<T>(address.get()).cast_mut())
    }

    pub static fn without_provenance(
        address: core.num.NonZero<usize>
    ): NonNull<T> {
        NonNull(core.ptr.without_provenance<T>(address.get()).cast_mut())
    }

    pub static fn dangling(): NonNull<T> {
        let address = unsafe {
            core.num.NonZero<usize>.new_unchecked(core.mem.align_of<T>())
        }
        NonNull(core.ptr.without_provenance<T>(address.get()).cast_mut())
    }

    pub fn is_aligned(): bool {
        self.pointer.addr() % core.mem.align_of<T>() == 0usize
    }

    pub fn align_offset(align: isize): usize {
        if align <= 0isize || (align & (align - 1isize)) != 0isize {
            core.panic.panic("align must be a positive power of two")
        }
        let alignment = align as usize
        let address = self.pointer.addr()
        let size = core.mem.size_of<T>()
        if alignment == 1usize { return 0usize }
        if size == 0usize {
            if address % alignment == 0usize { return 0usize }
            return usize.MAX
        }

        var reduced_size = size
        var modulus = alignment
        var divisor = 1usize
        while reduced_size % 2usize == 0usize && modulus % 2usize == 0usize {
            reduced_size /= 2usize
            modulus /= 2usize
            divisor *= 2usize
        }
        if address % divisor != 0usize { return usize.MAX }
        if modulus == 1usize { return 0usize }

        let target = (
            modulus - (address / divisor) % modulus
        ) % modulus
        let coefficient = reduced_size % modulus
        var inverse = 1usize
        var iteration = 0usize
        while iteration < 6usize {
            inverse = inverse.wrapping_mul(
                2usize.wrapping_sub(coefficient.wrapping_mul(inverse))
            )
            iteration += 1usize
        }
        target.wrapping_mul(inverse) % modulus
    }

    pub static fn slice_from_raw_parts(data: NonNull<T>, length: usize): NonNull<[T]> {
        let raw = RawSlice(data.pointer, length)
        // The transmute relies on slice-pointer metadata being a trailing element count.
        NonNull(unsafe { core.mem.transmute<ptr<mut [T]>>(raw) })
    }

    // Safety: the result must remain within or one past the allocated object.
    pub unsafe fn add(count: usize): NonNull<T> {
        NonNull(unsafe { self.pointer.add(count) })
    }

    // Safety: the result must remain within or one past the allocated object.
    pub unsafe fn sub(count: usize): NonNull<T> {
        NonNull(unsafe { self.pointer.sub(count) })
    }

    // Safety: the result must remain within or one past the allocated object.
    pub unsafe fn offset(count: isize): NonNull<T> {
        NonNull(unsafe { self.pointer.offset(count) })
    }

    // Safety: pointers must share an allocation and their distance fit `isize`.
    pub unsafe fn offset_from(origin: NonNull<T>): isize {
        unsafe { self.pointer.offset_from(origin.pointer) }
    }

    // Safety: pointers must share an allocation and `self` must follow `origin`.
    pub unsafe fn offset_from_unsigned(origin: NonNull<T>): usize {
        unsafe { self.pointer.offset_from_unsigned(origin.pointer) }
    }

    // Safety: the pointer must address initialized, aligned storage for `T`.
    pub unsafe fn `read`(): T {
        unsafe { core.ptr.`read`(self.pointer.cast_const()) }
    }

    // Safety: the pointer must address initialized storage for `T`.
    pub unsafe fn read_unaligned(): T {
        unsafe { core.ptr.read_unaligned(self.pointer.cast_const()) }
    }

    // Safety: the pointer must address valid storage for `T`.
    pub unsafe fn read_volatile(): T {
        unsafe { core.ptr.read_volatile(self.pointer.cast_const()) }
    }

    // Safety: pointer must be writable, `value` valid, and any old value handled.
    pub unsafe fn write(take value: T): Unit {
        unsafe { core.ptr.write(self.pointer, value) }
    }

    // Safety: pointer must be writable, `value` valid, and any old value handled.
    pub unsafe fn write_unaligned(take value: T): Unit {
        unsafe { core.ptr.write_unaligned(self.pointer, value) }
    }

    // Safety: pointer must be writable, `value` valid, and any old value handled.
    pub unsafe fn write_volatile(take value: T): Unit {
        unsafe { core.ptr.write_volatile(self.pointer, value) }
    }

    // Safety: range must be aligned and writable; each resulting `T` must be valid.
    pub unsafe fn write_bytes(value: u8, count: usize): Unit {
        unsafe { self.pointer.write_bytes(value, count) }
    }

    // Safety: the pointer must address initialized, aligned storage for `T`.
    pub unsafe fn replace(take value: T): T {
        let previous = unsafe { core.ptr.`read`(self.pointer.cast_const()) }
        unsafe { core.ptr.write(self.pointer, value) }
        previous
    }

    // Safety: both pointers must address valid storage for `T`.
    pub unsafe fn swap(other: NonNull<T>): Unit {
        unsafe { core.ptr.swap(self.pointer, other.pointer) }
    }

    // Safety: ranges must be valid; caller must preserve initialization and drop ownership.
    pub unsafe fn copy_from(source: ptr<read T>, count: usize): Unit {
        unsafe { core.ptr.`copy`(source, self.pointer, count) }
    }

    // Safety: valid nonoverlapping ranges; caller must preserve initialization/drop ownership.
    pub unsafe fn copy_from_nonoverlapping(source: ptr<read T>, count: usize): Unit {
        unsafe { core.ptr.`copy`(source, self.pointer, count) }
    }

    // Safety: ranges must be valid; caller must preserve initialization and drop ownership.
    pub unsafe fn copy_to(destination: ptr<mut T>, count: usize): Unit {
        unsafe { core.ptr.`copy`(self.pointer.cast_const(), destination, count) }
    }

    // Safety: valid nonoverlapping ranges; caller must preserve initialization/drop ownership.
    pub unsafe fn copy_to_nonoverlapping(destination: ptr<mut T>, count: usize): Unit {
        unsafe { core.ptr.`copy`(self.pointer.cast_const(), destination, count) }
    }
}

extend<T> NonNull<[T]> {
    pub fn len(): usize {
        let raw = unsafe { core.mem.transmute<RawSlice<T>>(self.pointer) }
        raw.length
    }

    pub fn is_empty(): bool { self.len() == 0usize }
}
