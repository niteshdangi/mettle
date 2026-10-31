import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.fmt
import package.core.hash.{Hash, Hasher}
import package.core.ops.{Deref, DerefMut}
import super.alloc.{Allocator, Global, AllocError, Layout, layout_of, layout_of_val, layout_unchecked, free_block, handle_alloc_error}
import package.core.clone.Clone
import package.core.slice.drop_values

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
    pub fn as_ptr(): ptr<mut T> { self.p }
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

// Safety: `p` came from `into_raw` (or an equivalent allocation of the
// dynamic layout of `T` by `a`) and holds an initialized `T`.
pub unsafe fn from_raw_in<T: unsized, A: Allocator>(p: ptr<mut T>, a: take A): Box<T, A> { Box(p, a) }
pub unsafe fn from_raw<T: unsized>(p: ptr<mut T>): Box<T> { Box(p, Global()) }


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

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<T: Transferable, A: Allocator + Transferable> Box<T, A> implements Transferable {}
unsafe extend<T: Shareable, A: Allocator + Shareable> Box<T, A> implements Shareable {}
