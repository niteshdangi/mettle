// Source-level companions of the compiler-owned `core.mem` module. `core.mem`
// cannot hold declarations, so what needs an interface bound lives here:
// `core.mem.take` resolves to `take` below, and `core.mem.ManuallyDrop<T>`
// gets its trait implementations. `ManuallyDrop` never runs the payload's
// destructor on its own; every implementation here only reads or builds the
// payload through the storage operations.
import super.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import super.fmt.{Debug, Formatter, Error}
import super.hash.{Hash, Hasher}
import super.clone.Clone
import super.default.Default
import super.ops.{Deref, DerefMut}

// Replaces the referent with its default value and returns the previous one.
// Spelled `core.mem.`take`(slot)` by callers.
pub fn `take`<T: Default>(dest: mut T): T { core.mem.replace(dest, T.(Default).default()) }

extend<T: Clone> core.mem.ManuallyDrop<T> implements Clone {
    fn clone(): core.mem.ManuallyDrop<T> { core.mem.ManuallyDrop.new(self.get_ref().clone()) }
}
extend<T: PartialEq> core.mem.ManuallyDrop<T> implements PartialEq {
    fn eq(other: read core.mem.ManuallyDrop<T>): bool { self.get_ref().eq(other.get_ref()) }
}
extend<T: Eq> core.mem.ManuallyDrop<T> implements Eq {}
extend<T: PartialOrd> core.mem.ManuallyDrop<T> implements PartialOrd {
    fn partial_cmp(other: read core.mem.ManuallyDrop<T>): Ordering? {
        self.get_ref().partial_cmp(other.get_ref())
    }
}
extend<T: Ord> core.mem.ManuallyDrop<T> implements Ord {
    fn cmp(other: read core.mem.ManuallyDrop<T>): Ordering { self.get_ref().cmp(other.get_ref()) }
}
extend<T: Hash> core.mem.ManuallyDrop<T> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.get_ref().hash(mut state) }
}
extend<T: Default> core.mem.ManuallyDrop<T> implements Default {
    static fn default(): core.mem.ManuallyDrop<T> { core.mem.ManuallyDrop.new(T.(Default).default()) }
}
extend<T: Debug> core.mem.ManuallyDrop<T> implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        var fields = try f.debug_struct("ManuallyDrop")
        try fields.field("value", self.get_ref())
        try fields.finish()
    }
}
extend<T> core.mem.ManuallyDrop<T> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get_ref() }
}
extend<T> core.mem.ManuallyDrop<T> implements DerefMut {
    type Target = T
    mut fn deref_mut(): mut T from self { self.get_mut() }
}

// Slice pointers are a data address followed by an element count.
copy type RawSlice<T> { data: ptr<mut T>; len: usize }

// A raw pointer that is never null. Equality, ordering and hashing follow the
// address; the pointer carries no ownership and no lifetime, so every access
// through it is unsafe and the caller guarantees validity. Zero is the only
// invalid address, so the address-taking constructors panic on zero instead of
// taking a non-zero integer type (the library has none).
pub copy type NonNull<T: unsized> { p: ptr<mut T> }

extend<T: unsized> NonNull<T> {
    // Wraps a raw pointer, or reports `none` for null.
    pub static fn new(p: ptr<mut T>): NonNull<T>? {
        if p.is_null() { none } else { present(NonNull(p)) }
    }
    // Safety: `p` must not be null.
    pub unsafe static fn new_unchecked(p: ptr<mut T>): NonNull<T> { NonNull(p) }
    pub static fn from_ref(value: read T): NonNull<T> { NonNull(core.ptr.from_ref(value).cast_mut()) }
    pub static fn from_mut(value: mut T): NonNull<T> { NonNull(core.ptr.from_mut(value)) }
    pub fn as_ptr(): ptr<mut T> { self.p }
    pub fn addr(): usize { self.p.addr() }
    pub fn expose_provenance(): usize { self.p.expose_provenance() }
    // Safety: the pointee must be initialized and not mutated while the view lives.
    pub unsafe fn as_ref(): read T from self { unsafe { read *self.p } }
    // Safety: the pointee must be initialized and not otherwise accessed while the view lives.
    pub mut unsafe fn as_mut(): mut T from self { unsafe { mut *self.p } }
    pub fn cast<U>(): NonNull<U> { NonNull(self.p.cast<U>()) }
    pub unsafe fn byte_add(count: usize): NonNull<T> { NonNull(unsafe { self.p.byte_add(count) }) }
    pub unsafe fn byte_sub(count: usize): NonNull<T> { NonNull(unsafe { self.p.byte_sub(count) }) }
    pub unsafe fn byte_offset(count: isize): NonNull<T> { NonNull(unsafe { self.p.byte_offset(count) }) }
    pub unsafe fn byte_offset_from(origin: NonNull<T>): isize { unsafe { self.p.byte_offset_from(origin.p) } }
    pub unsafe fn byte_offset_from_unsigned(origin: NonNull<T>): usize {
        unsafe { self.p.byte_offset_from_unsigned(origin.p) }
    }
    // Same address and metadata, new provenance-preserving address; zero panics.
    pub fn with_addr(address: usize): NonNull<T> {
        if address == 0usize { super.panic.panic("NonNull address must not be zero") }
        NonNull(self.p.with_addr(address))
    }
    pub unsafe fn drop_in_place(): Unit { unsafe { core.ptr.drop_in_place(self.p) } }
}

extend<T> NonNull<T> {
    // Well-aligned, non-null and never dereferenceable.
    pub static fn dangling(): NonNull<T> {
        NonNull(unsafe { core.mem.transmute<ptr<mut T>>(core.mem.align_of<T>()) })
    }
    pub static fn without_provenance(address: usize): NonNull<T> {
        if address == 0usize { super.panic.panic("NonNull address must not be zero") }
        NonNull(core.ptr.without_provenance<T>(address).cast_mut())
    }
    pub static fn with_exposed_provenance(address: usize): NonNull<T> {
        if address == 0usize { super.panic.panic("NonNull address must not be zero") }
        NonNull(core.ptr.with_exposed_provenance<T>(address).cast_mut())
    }
    pub unsafe fn add(count: usize): NonNull<T> { NonNull(unsafe { self.p.add(count) }) }
    pub unsafe fn sub(count: usize): NonNull<T> { NonNull(unsafe { self.p.sub(count) }) }
    pub unsafe fn offset(count: isize): NonNull<T> { NonNull(unsafe { self.p.offset(count) }) }
    pub unsafe fn offset_from(origin: NonNull<T>): isize { unsafe { self.p.offset_from(origin.p) } }
    pub unsafe fn offset_from_unsigned(origin: NonNull<T>): usize {
        unsafe { self.p.offset_from_unsigned(origin.p) }
    }
    pub fn is_aligned(): bool { self.p.addr() % core.mem.align_of<T>() == 0usize }
    // Elements to add so the address reaches `align`, or usize.MAX when no
    // element count can. `align` must be a power of two.
    pub fn align_offset(align: usize): usize {
        if align == 0usize || (align & (align - 1usize)) != 0usize {
            super.panic.panic("align_offset requires a power-of-two alignment")
        }
        let address = self.p.addr()
        let stride = core.mem.size_of<T>()
        var steps = 0usize
        while steps < align {
            if address.wrapping_add(steps.wrapping_mul(stride)) % align == 0usize { return steps }
            steps += 1usize
        }
        usize.MAX
    }
    pub unsafe fn `read`(): T { unsafe { core.ptr.`read`(self.p) } }
    pub unsafe fn read_unaligned(): T { unsafe { core.ptr.`read_unaligned`(self.p) } }
    pub unsafe fn read_volatile(): T { unsafe { core.ptr.`read_volatile`(self.p) } }
    pub unsafe fn write(value: take T): Unit { unsafe { core.ptr.write(self.p, value) } }
    pub unsafe fn write_unaligned(value: take T): Unit { unsafe { core.ptr.write_unaligned(self.p, value) } }
    pub unsafe fn write_volatile(value: take T): Unit { unsafe { core.ptr.write_volatile(self.p, value) } }
    pub unsafe fn write_bytes(value: u8, count: usize): Unit { unsafe { core.ptr.write_bytes(self.p, value, count) } }
    pub unsafe fn replace(value: take T): T { unsafe { core.ptr.replace(self.p, value) } }
    pub unsafe fn swap(with: NonNull<T>): Unit { unsafe { core.ptr.swap(self.p, with.p) } }
    pub unsafe fn copy_from(source: NonNull<T>, count: usize): Unit {
        unsafe { core.ptr.copy(source.p, self.p, count) }
    }
    pub unsafe fn copy_from_nonoverlapping(source: NonNull<T>, count: usize): Unit {
        unsafe { core.ptr.copy_nonoverlapping(source.p, self.p, count) }
    }
    pub unsafe fn copy_to(destination: NonNull<T>, count: usize): Unit {
        unsafe { core.ptr.copy(self.p, destination.p, count) }
    }
    pub unsafe fn copy_to_nonoverlapping(destination: NonNull<T>, count: usize): Unit {
        unsafe { core.ptr.copy_nonoverlapping(self.p, destination.p, count) }
    }
}

extend<T> NonNull<[T]> {
    pub static fn slice_from_raw_parts(data: NonNull<T>, len: usize): NonNull<[T]> {
        let raw = RawSlice(data.p, len)
        NonNull(unsafe { core.mem.transmute<ptr<mut [T]>>(raw) })
    }
    pub fn len(): usize {
        let raw = unsafe { core.mem.transmute<RawSlice<T>>(self.p) }
        raw.len
    }
    pub fn is_empty(): bool { self.len() == 0usize }
}

extend<T: unsized> NonNull<T> implements Clone { fn clone(): NonNull<T> { NonNull(self.p) } }
extend<T: unsized> NonNull<T> implements PartialEq {
    fn eq(other: read NonNull<T>): bool { core.ptr.eq(self.p, other.p) }
}
extend<T: unsized> NonNull<T> implements Eq {}
extend<T: unsized> NonNull<T> implements PartialOrd {
    fn partial_cmp(other: read NonNull<T>): Ordering? { present(self.cmp(other)) }
}
extend<T: unsized> NonNull<T> implements Ord {
    fn cmp(other: read NonNull<T>): Ordering {
        let left = self.p.addr()
        let right = other.p.addr()
        left.cmp(read right)
    }
}
extend<T: unsized> NonNull<T> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_usize(self.p.addr()) }
}
extend<T: unsized> NonNull<T> implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        var fields = try f.debug_tuple("NonNull")
        try fields.field(self.p.addr())
        try fields.finish()
    }
}
