import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.fmt
import package.core.hash.{Hash, Hasher}
import package.core.error.Error
import package.core.ops.{Deref, DerefMut}
import super.alloc.{Allocator, Global, AllocError, Layout, layout_of, layout_of_val, layout_unchecked, free_block, handle_alloc_error}
import package.core.clone.Clone
import package.core.borrow.{AsRef, Borrow}
import package.core.default.Default
import package.core.convert.{From, TryFrom}
import package.core.iter.{OwnedIterable, Iterator, ExactSizeIterator, BidirectionalIterator, FromItems}
import package.core.future.{Context, Future, Poll}
import package.core.slice.drop_values
import package.core.text.Text

// Unique owner of one heap value, tied to the allocator that produced it.
pub type Box<T: unsized, A: Allocator = super.alloc.Global> {
    p: ptr<mut T>
    a: A
    drop {
        let _free = unsafe { free_block(self.p.cast<u8>(), layout_of_val(self.get()), core.ptr.from_mut(self.a)) }
        unsafe { core.ptr.drop_in_place(self.p) }
    }
}

pub fn try_new_in<T, A: Allocator>(value: take T, allocator: take A): Box<T, A> throws AllocError {
    var a = allocator
    let raw = try a.allocate(layout_of<T>())
    unsafe { core.ptr.write(raw.cast<T>(), value) }
    Box(raw.cast<T>(), a)
}

pub fn new_in<T, A: Allocator>(value: take T, allocator: take A): Box<T, A> {
    let outcome = capture try_new_in(value, allocator)
    match take outcome {
        success(b) => b,
        failure(e) => handle_alloc_error(layout_of<T>())
    }
}

pub fn try_new<T>(value: take T): Box<T> throws AllocError { try try_new_in(value, Global()) }
pub fn new<T>(value: take T): Box<T> { new_in(value, Global()) }

pub fn try_new_uninit_in<T, A: Allocator>(
    allocator: take A
): Box<core.mem.MaybeUninit<T>, A> throws AllocError {
    try try_new_in(core.mem.MaybeUninit<T>.uninit(), allocator)
}
pub fn new_uninit_in<T, A: Allocator>(allocator: take A): Box<core.mem.MaybeUninit<T>, A> {
    let result = capture try_new_uninit_in<T, A>(allocator)
    match take result {
        success(owner) => owner,
        failure(_) => handle_alloc_error(layout_of<T>())
    }
}
pub fn try_new_uninit<T>(): Box<core.mem.MaybeUninit<T>> throws AllocError {
    try try_new_uninit_in<T, Global>(Global())
}
pub fn new_uninit<T>(): Box<core.mem.MaybeUninit<T>> { new_uninit_in<T, Global>(Global()) }

pub fn try_new_zeroed_in<T, A: Allocator>(
    allocator: take A
): Box<core.mem.MaybeUninit<T>, A> throws AllocError {
    try try_new_in(core.mem.MaybeUninit<T>.zeroed(), allocator)
}
pub fn new_zeroed_in<T, A: Allocator>(allocator: take A): Box<core.mem.MaybeUninit<T>, A> {
    let result = capture try_new_zeroed_in<T, A>(allocator)
    match take result {
        success(owner) => owner,
        failure(_) => handle_alloc_error(layout_of<T>())
    }
}
pub fn try_new_zeroed<T>(): Box<core.mem.MaybeUninit<T>> throws AllocError {
    try try_new_zeroed_in<T, Global>(Global())
}
pub fn new_zeroed<T>(): Box<core.mem.MaybeUninit<T>> { new_zeroed_in<T, Global>(Global()) }

copy type RawSlice<T> { data: ptr<read T>; len: usize }

fn dangling_slot<T>(): ptr<mut T> {
    let align = core.mem.align_of<T>()
    unsafe { core.mem.transmute<ptr<mut T>>(align) }
}

fn slice_pointer<T>(data: ptr<mut T>, len: usize): ptr<mut [T]> {
    let raw = RawSlice(data.cast_const(), len)
    unsafe { core.mem.transmute<ptr<mut [T]>>(raw) }
}

fn fill_slice<T, A: Allocator>(
    len: usize,
    allocator: take A,
    zeroed: bool
): Box<[core.mem.MaybeUninit<T>], A> throws AllocError {
    var allocator = allocator
    let size = core.mem.size_of<core.mem.MaybeUninit<T>>()
    let align = core.mem.align_of<core.mem.MaybeUninit<T>>()
    if len == 0usize || size == 0usize {
        return Box(slice_pointer(dangling_slot<core.mem.MaybeUninit<T>>(), len), allocator)
    }
    let bytes = match len.checked_mul(size) {
        present(value) => value,
        none => throw AllocError(0xffffffffffffffffusize, align)
    }
    let layout = unsafe { layout_unchecked(bytes, align) }
    let raw = try allocator.allocate(layout)
    let base = raw.cast<core.mem.MaybeUninit<T>>()
    var index = 0usize
    while index < len {
        let slot = if zeroed {
            core.mem.MaybeUninit<T>.zeroed()
        } else {
            core.mem.MaybeUninit<T>.uninit()
        }
        unsafe { core.ptr.write(base.add(index), slot) }
        index += 1usize
    }
    Box(slice_pointer(base, len), allocator)
}

pub fn try_new_uninit_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Box<[core.mem.MaybeUninit<T>], A> throws AllocError {
    try fill_slice<T, A>(len, allocator, false)
}
pub fn new_uninit_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Box<[core.mem.MaybeUninit<T>], A> {
    let result = capture try_new_uninit_slice_in<T, A>(len, allocator)
    match take result {
        success(owner) => owner,
        failure(_) => handle_alloc_error(layout_of<T>())
    }
}
pub fn try_new_uninit_slice<T>(len: usize): Box<[core.mem.MaybeUninit<T>]> throws AllocError {
    try try_new_uninit_slice_in<T, Global>(len, Global())
}
pub fn new_uninit_slice<T>(len: usize): Box<[core.mem.MaybeUninit<T>]> {
    new_uninit_slice_in<T, Global>(len, Global())
}
pub fn try_new_zeroed_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Box<[core.mem.MaybeUninit<T>], A> throws AllocError {
    try fill_slice<T, A>(len, allocator, true)
}
pub fn new_zeroed_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Box<[core.mem.MaybeUninit<T>], A> {
    let result = capture try_new_zeroed_slice_in<T, A>(len, allocator)
    match take result {
        success(owner) => owner,
        failure(_) => handle_alloc_error(layout_of<T>())
    }
}
pub fn try_new_zeroed_slice<T>(len: usize): Box<[core.mem.MaybeUninit<T>]> throws AllocError {
    try try_new_zeroed_slice_in<T, Global>(len, Global())
}
pub fn new_zeroed_slice<T>(len: usize): Box<[core.mem.MaybeUninit<T>]> {
    new_zeroed_slice_in<T, Global>(len, Global())
}

extend<T> Box<T> {
    pub static fn new(value: take T): Box<T> { new_in(value, Global()) }
    pub static fn new_uninit(): Box<core.mem.MaybeUninit<T>> { new_uninit_in<T, Global>(Global()) }
    pub static fn new_zeroed(): Box<core.mem.MaybeUninit<T>> { new_zeroed_in<T, Global>(Global()) }
    pub static fn new_uninit_slice(len: usize): Box<[core.mem.MaybeUninit<T>]> {
        new_uninit_slice_in<T, Global>(len, Global())
    }
    pub static fn new_zeroed_slice(len: usize): Box<[core.mem.MaybeUninit<T>]> {
        new_zeroed_slice_in<T, Global>(len, Global())
    }
}

extend<T: unsized, A: Allocator> Box<T, A> {
    pub fn get(): read T from self { unsafe { read *self.p } }
    pub mut fn get_mut(): mut T from self { unsafe { mut *self.p } }
    pub fn allocator(): read A from self { read self.a }
    pub fn as_ptr(): ptr<read T> { self.p.cast_const() }
    pub mut fn as_mut_ptr(): ptr<mut T> { self.p }
    // Ownership conversion: the caller becomes responsible for the block and
    // must rebuild it with `from_raw_in` using a compatible allocator.
    pub take fn into_raw(): (ptr<mut T>, A) {
        unsafe {
            let p = self.p
            let a = core.ptr.`read`(core.ptr.from_ref(self.a))
            core.mem.forget(take self)
            (p, a)
        }
    }
    // Like `into_raw`, but the pointer is statically non-null, which every box
    // pointer is (dangling and zero-sized payloads use the alignment address).
    pub take fn into_non_null(): (core.ptr.NonNull<T>, A) {
        let raw = self.into_raw()
        (unsafe { core.ptr.NonNull<T>.new_unchecked(raw.0) }, raw.1)
    }
    // The allocator is intentionally retained with the leaked allocation.
    pub take fn leak(): ptr<mut T> {
        let p = self.p
        core.mem.forget(take self)
        p
    }
}

extend<T, A: Allocator> Box<core.mem.MaybeUninit<T>, A> {
    // Safety: the caller initialized the payload before taking ownership as T.
    pub take unsafe fn assume_init(): Box<T, A> {
        let raw = self.into_raw()
        unsafe { from_raw_in(raw.0.cast<T>(), raw.1) }
    }
    pub mut fn write(value: take T): mut T from self { self.get_mut().write(value) }
}

extend<T, A: Allocator> Box<T, A> {
    // Moves the value out and releases the block without dropping the value.
    pub take fn into_inner(): T {
        unsafe {
            let p = self.p
            let v = core.ptr.`read`(p)
            var a = core.ptr.`read`(core.ptr.from_ref(self.a))
            a.deallocate(p.cast<u8>(), layout_of<T>())
            core.mem.forget(take self)
            v
        }
    }
}

extend<A: Allocator> Box<any core.any.Any, A> {
    // Recovers the concrete box when the erased payload is a `T`; otherwise
    // the box is returned unchanged.
    pub take fn downcast<T>(): Box<T, A> throws Box<any core.any.Any, A> {
        if !core.any.is<T>(self.get()) { throw self }
        let raw = self.into_raw()
        unsafe { from_raw_in(raw.0.cast<T>(), raw.1) }
    }
}

// Safety: `p` came from `into_raw` (or an equivalent allocation of the
// dynamic layout of `T` by `a`) and holds an initialized `T`.
pub unsafe fn from_raw_in<T: unsized, A: Allocator>(p: ptr<mut T>, a: take A): Box<T, A> { Box(p, a) }
pub unsafe fn from_raw<T: unsized>(p: ptr<mut T>): Box<T> { Box(p, Global()) }
// Safety: same contract as `from_raw_in`; `p` came from `into_non_null`.
pub unsafe fn from_non_null_in<T: unsized, A: Allocator>(p: core.ptr.NonNull<T>, a: take A): Box<T, A> {
    Box(p.as_ptr(), a)
}
pub unsafe fn from_non_null<T: unsized>(p: core.ptr.NonNull<T>): Box<T> { Box(p.as_ptr(), Global()) }


// A box is transparent: comparison, hashing and formatting delegate to the payload.
extend<T: unsized, A: Allocator> Box<T, A> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get() }
}
extend<T: unsized, A: Allocator> Box<T, A> implements DerefMut {
    type Target = T
    mut fn deref_mut(): mut T from self { self.get_mut() }
}
extend<T: Clone, A: Allocator + Clone> Box<T, A> implements Clone {
    fn clone(): Box<T, A> { new_in(self.get().clone(), self.a.clone()) }
}
extend<T: PartialEq, A: Allocator> Box<T, A> implements PartialEq {
    fn eq(other: read Box<T, A>): bool { self.get().eq(other.get()) }
}
extend<T: Eq, A: Allocator> Box<T, A> implements Eq {}
extend<T: PartialOrd, A: Allocator> Box<T, A> implements PartialOrd {
    fn partial_cmp(other: read Box<T, A>): Ordering? { self.get().partial_cmp(other.get()) }
}
extend<T: Ord, A: Allocator> Box<T, A> implements Ord {
    fn cmp(other: read Box<T, A>): Ordering { self.get().cmp(other.get()) }
}
extend<T: Hash, A: Allocator> Box<T, A> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.get().hash(mut state) }
}
extend<T: fmt.Display, A: Allocator> Box<T, A> implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try T.(fmt.Display).fmt(self.get(), mut f) }
}
extend<T: fmt.Debug, A: Allocator> Box<T, A> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try T.(fmt.Debug).fmt(self.get(), mut f) }
}
extend<T: Error, A: Allocator> Box<T, A> implements Error {
    fn source<region r>(receiver self: read Box<T, A> from r): (read any Error from r)? {
        T.(Error).source(self.get())
    }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<T: Transferable, A: Allocator + Transferable> Box<T, A> implements Transferable {}
unsafe extend<T: Shareable, A: Allocator + Shareable> Box<T, A> implements Shareable {}

extend<T: unsized, A: Allocator> Box<T, A> implements AsRef<T> {
    fn as_ref(): read T from self { self.get() }
}
extend<T: unsized, A: Allocator> Box<T, A> implements Borrow<T> {
    fn borrow(): read T from self { self.get() }
}
extend<T: Default, A: Allocator + Default> Box<T, A> implements Default {
    static fn default(): Box<T, A> { new_in(T.(Default).default(), A.(Default).default()) }
}
extend<T> Box<T> implements From<T> {
    static fn `from`(value: take T): Box<T> { new(value) }
}

extend<A: Allocator> Box<Text, A> {
    // Text and [u8] have the same byte extent and metadata; u8 has no drop glue.
    pub take fn into_boxed_bytes(): Box<[u8], A> {
        let raw = self.into_raw()
        let bytes = unsafe { core.mem.transmute<ptr<mut [u8]>>(raw.0) }
        unsafe { from_raw_in(bytes, raw.1) }
    }
}

// Iteration, hashing and polling forward to the payload; the box only owns it.
extend<I: Iterator, A: Allocator> Box<I, A> implements Iterator {
    type Item = I.Item
    mut fn next(): I.Item? { self.get_mut().next() }
    fn size_hint(): (usize, usize?) { self.get().size_hint() }
}
extend<I: BidirectionalIterator, A: Allocator> Box<I, A> implements BidirectionalIterator {
    mut fn next_back(): I.(Iterator).Item? { self.get_mut().next_back() }
}
extend<I: ExactSizeIterator, A: Allocator> Box<I, A> implements ExactSizeIterator {
    fn len(): usize { self.get().len() }
}
extend<H: Hasher, A: Allocator> Box<H, A> implements Hasher {
    mut fn write(bytes: read [u8]): Unit { self.get_mut().write(bytes) }
    fn finish(): u64 { self.get().finish() }
}
// The payload has a stable address while the box lives, so a pinned box
// projects to a pinned payload (as `Erased` does for its raw allocation).
extend<F: Future, A: Allocator> Box<F, A> implements Future {
    type Output = F.Output
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<F.Output> {
        let me = unsafe { self.get_unchecked_mut() }
        unsafe { core.pin.Pin.new_unchecked(me.get_mut()).poll(mut cx) }
    }
}

extend<T> Box<[T]> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(items: take I): Box<[T]> {
        let collected: super.vec.List<T> = core.iter.collect(items)
        collected.into_boxed_slice()
    }
}
extend<T, const N: usize> Box<[T]> implements From<[T; N]> {
    static fn `from`(value: take [T; N]): Box<[T]> { super.vec.from_array(value).into_boxed_slice() }
}
// Fails with the original box when the length differs from `N`.
extend<T, A: Allocator, const N: usize> Box<[T; N], A> implements TryFrom<Box<[T], A>> {
    type Error = Box<[T], A>
    static fn try_from(value: take Box<[T], A>): (Box<[T; N], A> throws Box<[T], A>) {
        if value.get().len() != N { return failure(value) }
        let raw = value.into_raw()
        success(unsafe { from_raw_in(raw.0.cast<[T; N]>(), raw.1) })
    }
}
