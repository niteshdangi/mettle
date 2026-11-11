import package.core.iter.{FromItems, OwnedIterable}
// Atomically reference-counted shared owner. Counting is atomic; that makes
// the handles themselves thread-safe, not the payload: an `Arc<T>` crosses or
// is shared between threads only when `T` is both Transferable and Shareable.
import super.alloc.{Allocator, Global, AllocError, Layout, layout_of, layout_array, extend_layout, handle_alloc_error, layout_unchecked}
import package.core.borrow.{AsRef, Borrow}
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.clone.Clone
import package.core.convert.{From, TryFrom}
import package.core.default.Default
import package.core.error.Error
import package.core.fmt
import package.core.hash.{Hash, Hasher}
import package.core.ops.Deref
import package.core.text.Text
import super.vec.slice_ptr_mut

type ArcHeader {
    strong: core.sync.atomic.AtomicUsize
    wk: core.sync.atomic.AtomicUsize
    allocation: Layout
}

// Non-empty raw handles own one strong or weak count and preserve slice or
// witness metadata. Empty weak tokens have a null header and own no count.
pub type RawArc<T: unsized, A: Allocator = Global> {
    p: ptr<mut T>
    h: ptr<mut ArcHeader>
    a: A
}
pub type RawWeak<T: unsized, A: Allocator = Global> {
    p: ptr<mut T>
    h: ptr<mut ArcHeader>
    a: A
}
extend<T: unsized, A: Allocator> RawArc<T, A> {
    pub fn as_ptr(): ptr<mut T> { self.p }
}
extend<T: unsized, A: Allocator> RawWeak<T, A> {
    pub fn as_ptr(): ptr<mut T> { self.p }
}

fn allocation_layout<T>(): (Layout, usize) throws AllocError {
    let result = capture extend_layout(layout_of<ArcHeader>(), layout_of<T>())
    match take result {
        success((layout, offset)) => (layout.pad_to_align(), offset),
        failure(error) => throw AllocError(error.size, error.align)
    }
}

fn slice_allocation_layout<T>(len: usize): (Layout, usize, Layout) throws AllocError {
    let payload_result = capture layout_array<core.mem.MaybeUninit<T>>(len)
    let payload = match take payload_result {
        success(layout) => layout,
        failure(error) => throw AllocError(error.size, error.align)
    }
    let allocation_result = capture extend_layout(layout_of<ArcHeader>(), payload)
    let (allocation, offset) = match take allocation_result {
        success((layout, offset)) => (layout.pad_to_align(), offset),
        failure(error) => throw AllocError(error.size, error.align)
    }
    (allocation, offset, payload)
}

// The payload pointer carries slice or witness metadata; the separate header
// pointer keeps count access independent of that metadata.
pub type Arc<T: unsized, A: Allocator = Global> {
    p: ptr<mut T>
    h: ptr<mut ArcHeader>
    a: A
    drop {
        unsafe {
            let b = self.h
            // Release publishes this owner's uses of the payload; the owner
            // that observes the last count acquires all of them before drop.
            if (*b).strong.fetch_sub(1usize, core.sync.atomic.Ordering.Release) == 1usize {
                core.sync.atomic.fence(core.sync.atomic.Ordering.Acquire)
                let _implicit = WeakRelease(b, core.ptr.from_mut(self.a))
                core.ptr.drop_in_place(self.p)
            }
        }
    }
}

// Non-owning handle: keeps the block (not the payload) alive.
pub type Weak<T: unsized, A: Allocator = Global> {
    p: ptr<mut T>
    h: ptr<mut ArcHeader>
    a: A
    drop {
        if self.h != core.ptr.null_mut<ArcHeader>() {
            unsafe {
                let _guard = WeakRelease(self.h, core.ptr.from_mut(self.a))
            }
        }
    }
}

// Drops one weak reference and frees the block when none remain.
type WeakRelease<A: Allocator> {
    p: ptr<mut ArcHeader>
    a: ptr<mut A>
    drop {
        unsafe {
            let b = self.p
            if (*b).wk.fetch_sub(1usize, core.sync.atomic.Ordering.Release) == 1usize {
                core.sync.atomic.fence(core.sync.atomic.Ordering.Acquire)
                (*self.a).deallocate(b.cast<u8>(), (*b).allocation)
            }
        }
    }
}

pub fn try_new_in<T, A: Allocator>(take value: T, take allocator: A): Arc<T, A> throws AllocError {
    var a = allocator
    let (layout, offset) = try allocation_layout<T>()
    let raw = try a.allocate(layout)
    let b = raw.cast<ArcHeader>()
    let p = unsafe { raw.add(offset) }.cast<T>()
    unsafe {
        core.ptr.write(b, ArcHeader(core.sync.atomic.AtomicUsize.new(1usize),
                                    core.sync.atomic.AtomicUsize.new(1usize),
                                    layout))
        core.ptr.write(p, value)
    }
    Arc(p, b, a)
}
pub fn new_in<T, A: Allocator>(take value: T, take allocator: A): Arc<T, A> {
    let outcome = capture try_new_in(value, allocator)
    match take outcome {
        success(r) => r,
        failure(e) => handle_alloc_error(unsafe { layout_unchecked(e.size, e.align) })
    }
}
pub fn new<T>(take value: T): Arc<T> { new_in(value, Global()) }
pub fn try_new<T>(take value: T): Arc<T> throws AllocError { try try_new_in(value, Global()) }

// An empty Weak has no allocation or count; its null header is the sentinel.
pub fn new_weak<T>(): Weak<T> {
    Weak(core.ptr.null_mut<T>(), core.ptr.null_mut<ArcHeader>(), Global())
}

extend<T> Weak<T> implements package.core.default.Default {
    static fn default(): Weak<T> { new_weak<T>() }
}

pub fn try_new_uninit_in<T, A: Allocator>(
    take allocator: A
): Arc<core.mem.MaybeUninit<T>, A> throws AllocError {
    try try_new_in(core.mem.MaybeUninit<T>.uninit(), allocator)
}
pub fn new_uninit_in<T, A: Allocator>(
    take allocator: A
): Arc<core.mem.MaybeUninit<T>, A> {
    let result = capture try_new_uninit_in<T, A>(allocator)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}
pub fn try_new_uninit<T>(): Arc<core.mem.MaybeUninit<T>> throws AllocError {
    try try_new_uninit_in<T, Global>(Global())
}
pub fn new_uninit<T>(): Arc<core.mem.MaybeUninit<T>> { new_uninit_in<T, Global>(Global()) }

pub fn try_new_zeroed_in<T, A: Allocator>(
    take allocator: A
): Arc<core.mem.MaybeUninit<T>, A> throws AllocError {
    try try_new_in(core.mem.MaybeUninit<T>.zeroed(), allocator)
}
pub fn new_zeroed_in<T, A: Allocator>(
    take allocator: A
): Arc<core.mem.MaybeUninit<T>, A> {
    let result = capture try_new_zeroed_in<T, A>(allocator)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}
pub fn try_new_zeroed<T>(): Arc<core.mem.MaybeUninit<T>> throws AllocError {
    try try_new_zeroed_in<T, Global>(Global())
}
pub fn new_zeroed<T>(): Arc<core.mem.MaybeUninit<T>> { new_zeroed_in<T, Global>(Global()) }

fn try_new_slice_in<T, A: Allocator>(
    len: usize,
    take allocator: A,
    zeroed: bool
): Arc<[core.mem.MaybeUninit<T>], A> throws AllocError {
    var a = allocator
    let (layout, offset, payload) = try slice_allocation_layout<T>(len)
    let raw = try a.allocate(layout)
    let h = raw.cast<ArcHeader>()
    let data = unsafe { raw.add(offset) }.cast<core.mem.MaybeUninit<T>>()
    unsafe {
        core.ptr.write(h, ArcHeader(
            core.sync.atomic.AtomicUsize.new(1usize),
            core.sync.atomic.AtomicUsize.new(1usize),
            layout
        ))
        if zeroed && payload.size() != 0usize {
            // Only the payload extent is zeroed; the reference-count header
            // remains initialized, and all payload slots remain MaybeUninit.
            core.ptr.write_bytes(data.cast<u8>(), 0u8, payload.size())
        }
    }
    Arc(slice_ptr_mut(data, len), h, a)
}

pub fn try_new_uninit_slice_in<T, A: Allocator>(
    len: usize,
    take allocator: A
): Arc<[core.mem.MaybeUninit<T>], A> throws AllocError {
    try try_new_slice_in<T, A>(len, allocator, false)
}

pub fn new_uninit_slice_in<T, A: Allocator>(
    len: usize,
    take allocator: A
): Arc<[core.mem.MaybeUninit<T>], A> {
    let result = capture try_new_uninit_slice_in<T, A>(len, allocator)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe {
            layout_unchecked(error.size, error.align)
        })
    }
}

pub fn try_new_uninit_slice<T>(
    len: usize
): Arc<[core.mem.MaybeUninit<T>]> throws AllocError {
    try try_new_uninit_slice_in<T, Global>(len, Global())
}

pub fn new_uninit_slice<T>(len: usize): Arc<[core.mem.MaybeUninit<T>]> {
    new_uninit_slice_in<T, Global>(len, Global())
}

pub fn try_new_zeroed_slice_in<T, A: Allocator>(
    len: usize,
    take allocator: A
): Arc<[core.mem.MaybeUninit<T>], A> throws AllocError {
    try try_new_slice_in<T, A>(len, allocator, true)
}

pub fn new_zeroed_slice_in<T, A: Allocator>(
    len: usize,
    take allocator: A
): Arc<[core.mem.MaybeUninit<T>], A> {
    let result = capture try_new_zeroed_slice_in<T, A>(len, allocator)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe {
            layout_unchecked(error.size, error.align)
        })
    }
}

pub fn try_new_zeroed_slice<T>(
    len: usize
): Arc<[core.mem.MaybeUninit<T>]> throws AllocError {
    try try_new_zeroed_slice_in<T, Global>(len, Global())
}

pub fn new_zeroed_slice<T>(len: usize): Arc<[core.mem.MaybeUninit<T>]> {
    new_zeroed_slice_in<T, Global>(len, Global())
}

// Copies only from a validated Text view, preserving Text's UTF-8 invariant.
pub fn try_copy_text_in<A: Allocator>(read value: Text, take allocator: A): Arc<Text, A> throws AllocError {
    var a = allocator
    let bytes = value.as_bytes()
    let result = capture extend_layout(layout_of<ArcHeader>(), super.alloc.layout_of_val(bytes))
    let (layout, offset) = match take result {
        success((layout, offset)) => (layout.pad_to_align(), offset),
        failure(error) => throw AllocError(error.size, error.align)
    }
    let raw = try a.allocate(layout)
    let h = raw.cast<ArcHeader>()
    let data = unsafe { raw.add(offset) }.cast<u8>()
    unsafe {
        core.ptr.write(h, ArcHeader(core.sync.atomic.AtomicUsize.new(1usize),
                                    core.sync.atomic.AtomicUsize.new(1usize),
                                    layout))
        core.ptr.copy(package.core.slice.data(bytes), data, bytes.len())
    }
    let slice = slice_ptr_mut(data, bytes.len())
    let text = unsafe { core.mem.transmute<ptr<mut Text>>(slice) }
    Arc(text, h, a)
}

pub fn copy_text_in<A: Allocator>(read value: Text, take allocator: A): Arc<Text, A> {
    let outcome = capture try_copy_text_in(value, allocator)
    match take outcome {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}

pub fn try_copy_text(read value: Text): Arc<Text> throws AllocError {
    try try_copy_text_in(value, Global())
}
pub fn copy_text(read value: Text): Arc<Text> { copy_text_in(value, Global()) }

// Transfer and sharing of the handles require the payload to be both
// Transferable and Shareable (the last owner may drop it on any thread, and
// every owner may read it concurrently) and the allocator to cross threads.
unsafe extend<T: Transferable + Shareable + unsized, A: Allocator + Transferable> Arc<T, A> implements Transferable {}
unsafe extend<T: Transferable + Shareable + unsized, A: Allocator + Shareable> Arc<T, A> implements Shareable {}
unsafe extend<T: Transferable + Shareable + unsized, A: Allocator + Transferable> Weak<T, A> implements Transferable {}
unsafe extend<T: Transferable + Shareable + unsized, A: Allocator + Shareable> Weak<T, A> implements Shareable {}

// Increments a live count; overflow would let it wrap to zero and free a live
// payload, so it aborts.
unsafe fn increment(count: ptr<mut core.sync.atomic.AtomicUsize>) {
    let previous = (*count).fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
    if previous > 0x7fffffffffffffffusize { core.intrinsics.abort() }
}

unsafe fn increment_weak(h: ptr<mut ArcHeader>): Unit {
    var current = (*h).wk.load(core.sync.atomic.Ordering.Relaxed)
    while true {
        if current == usize.MAX {
            current = (*h).wk.load(core.sync.atomic.Ordering.Relaxed)
            continue
        }
        if current > 0x7fffffffffffffffusize { core.intrinsics.abort() }
        match (*h).wk.compare_exchange_weak(
            current, current + 1usize,
            core.sync.atomic.Ordering.Acquire, core.sync.atomic.Ordering.Relaxed
        ) {
            success(_) => { return },
            failure(seen) => { current = seen }
        }
    }
}

unsafe fn is_unique(h: ptr<mut ArcHeader>): bool {
    if (*h).wk.compare_exchange(
        1usize, usize.MAX,
        core.sync.atomic.Ordering.Acquire, core.sync.atomic.Ordering.Relaxed
    ).is_failure() { return false }
    // Locking the implicit weak excludes downgrade until the strong check completes.
    let unique = (*h).strong.load(core.sync.atomic.Ordering.Acquire) == 1usize
    (*h).wk.store(1usize, core.sync.atomic.Ordering.Release)
    unique
}

pub fn try_new_cyclic_in<T, A: Allocator + Clone, F: take fn(read Weak<T, A>): T>(
    take allocator: A,
    take make: F
): Arc<T, A> throws AllocError {
    var a = allocator
    let weak_allocator = a.clone()
    let (layout, offset) = try allocation_layout<T>()
    let raw = try a.allocate(layout)
    let h = raw.cast<ArcHeader>()
    let p = unsafe { raw.add(offset) }.cast<T>()
    // Keep upgrades disabled until the payload is initialized; the guard
    // releases the implicit weak count if the constructor unwinds.
    unsafe {
        core.ptr.write(h, ArcHeader(
            core.sync.atomic.AtomicUsize.new(0usize),
            core.sync.atomic.AtomicUsize.new(2usize),
            layout
        ))
    }
    let weak_handle = Weak(p, h, weak_allocator)
    let _guard = WeakRelease(h, core.ptr.from_mut(a))
    let value = make(read weak_handle)
    unsafe {
        core.ptr.write(p, value)
        (*h).strong.store(1usize, core.sync.atomic.Ordering.Release)
    }
    core.mem.forget(take _guard)
    Arc(p, h, a)
}
pub fn new_cyclic_in<T, A: Allocator + Clone, F: take fn(read Weak<T, A>): T>(
    take allocator: A,
    take make: F
): Arc<T, A> {
    let result = capture try_new_cyclic_in<T, A, F>(allocator, make)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}
pub fn try_new_cyclic<T, F: take fn(read Weak<T>): T>(take make: F): Arc<T> throws AllocError {
    try try_new_cyclic_in<T, Global, F>(Global(), make)
}
pub fn new_cyclic<T, F: take fn(read Weak<T>): T>(take make: F): Arc<T> {
    new_cyclic_in<T, Global, F>(Global(), make)
}

extend<T: unsized, A: Allocator + Clone> Arc<T, A> {
    // Another strong owner of the same payload; the payload is not cloned.
    pub fn retain(): Arc<T, A> {
        let allocator = self.a.clone()
        unsafe { increment(core.ptr.from_mut((*self.h).strong)) }
        Arc(self.p, self.h, allocator)
    }
    pub fn downgrade(): Weak<T, A> {
        let allocator = self.a.clone()
        unsafe { increment_weak(self.h) }
        Weak(self.p, self.h, allocator)
    }
}
extend<T: unsized, A: Allocator + Clone> Arc<T, A> implements Clone {
    fn clone(): Arc<T, A> { self.retain() }
}

extend<T, A: Allocator> Arc<core.mem.MaybeUninit<T>, A> {
    // Safety: the caller initialized the payload before taking ownership as T.
    pub take unsafe fn assume_init(): Arc<T, A> {
        let raw = self.into_raw()
        unsafe { from_raw(RawArc(raw.p.cast<T>(), raw.h, raw.a)) }
    }
}

extend<T, A: Allocator> Arc<[core.mem.MaybeUninit<T>], A> {
    // Safety: every element is initialized as T; element layout and length
    // metadata are unchanged by replacing MaybeUninit<T> with T.
    pub take unsafe fn assume_init(): Arc<[T], A> {
        let raw = self.into_raw()
        let slice = unsafe { core.mem.transmute<ptr<mut [T]>>(raw.p) }
        unsafe { from_raw(RawArc(slice, raw.h, raw.a)) }
    }
}

extend<T: unsized, A: Allocator> Arc<T, A> {
    pub fn get(): read T from self { unsafe { read *self.p } }
    // The pointer is valid while this strong owner remains alive.
    pub fn as_ptr(): ptr<read T> { self.p.cast_const() }
    pub fn strong_count(): usize { unsafe { (*self.h).strong.load(core.sync.atomic.Ordering.Acquire) } }
    pub fn weak_count(): usize {
        unsafe {
            let strong = (*self.h).strong.load(core.sync.atomic.Ordering.Acquire)
            let weak_total = (*self.h).wk.load(core.sync.atomic.Ordering.Acquire)
            if weak_total == usize.MAX { return 0usize }
            if strong == 0usize || weak_total == 0usize { weak_total } else { weak_total - 1usize }
        }
    }
    pub fn ptr_eq(read other: Arc<T, A>): bool { self.h == other.h }
    // The weak-count lock synchronizes uniqueness with concurrent downgrade.
    pub mut fn get_mut(): (mut T from self)? {
        if unsafe { is_unique(self.h) } { present(unsafe { mut *self.p }) } else { none }
    }
}

extend<T, A: Allocator> Arc<T, A> {
    // Moves the payload out when this is the only strong owner; otherwise the
    // handle is returned unchanged. Weak handles may remain but can no longer
    // upgrade.
    pub take fn try_unwrap(): T throws Arc<T, A> {
        unsafe {
            let b = self.h
            if (*b).strong.compare_exchange(1usize, 0usize, core.sync.atomic.Ordering.Acquire,
                                            core.sync.atomic.Ordering.Relaxed).is_failure() { throw self }
            let value = core.ptr.`read`(self.p)
            var a = core.ptr.`read`(core.ptr.from_ref(self.a))
            core.mem.forget(take self)
            let _implicit = WeakRelease(b, core.ptr.from_mut(a))
            value
        }
    }
    // The payload if this was the only strong owner; otherwise releases this
    // handle and returns none.
    pub take fn into_inner(): T? {
        let raw = self.into_raw()
        unsafe {
            if (*raw.h).strong.fetch_sub(1usize, core.sync.atomic.Ordering.Release) != 1usize {
                return none
            }
            core.sync.atomic.fence(core.sync.atomic.Ordering.Acquire)
            let value = core.ptr.`read`(raw.p)
            var allocator = raw.a
            let _implicit = WeakRelease(raw.h, core.ptr.from_mut(allocator))
            present(value)
        }
    }
    pub take fn unwrap_or_clone(): T where T: Clone {
        let result = capture self.try_unwrap()
        match take result {
            success(value) => value,
            failure(owner) => owner.get().clone()
        }
    }
}

extend<T: unsized, A: Allocator> Arc<T, A> {
    pub take fn into_raw(): RawArc<T, A> {
        unsafe {
            let p = self.p
            let h = self.h
            let a = core.ptr.`read`(core.ptr.from_ref(self.a))
            core.mem.forget(take self)
            RawArc(p, h, a)
        }
    }
}
pub unsafe fn from_raw<T: unsized, A: Allocator>(take raw: RawArc<T, A>): Arc<T, A> {
    Arc(raw.p, raw.h, raw.a)
}
// Creates a second raw ownership token; consume both tokens exactly once.
pub unsafe fn increment_strong_count<T: unsized, A: Allocator + Clone>(
    read raw: RawArc<T, A>
): RawArc<T, A> {
    let allocator = raw.a.clone()
    unsafe { increment(core.ptr.from_mut((*raw.h).strong)) }
    RawArc(raw.p, raw.h, allocator)
}
pub unsafe fn decrement_strong_count<T: unsized, A: Allocator>(take raw: RawArc<T, A>): Unit {
    let _owner = unsafe { from_raw(raw) }
}

extend<T: unsized, A: Allocator + Clone> Weak<T, A> {
    // Succeeds only while a strong owner exists; the count only moves up from
    // a nonzero value, so a block already being destroyed is never revived.
    pub fn upgrade(): Arc<T, A>? {
        if self.h == core.ptr.null_mut<ArcHeader>() { return none }
        unsafe {
            let b = self.h
            var current = (*b).strong.load(core.sync.atomic.Ordering.Relaxed)
            while current != 0usize {
                if current > 0x7fffffffffffffffusize { core.intrinsics.abort() }
                let allocator = self.a.clone()
                match (*b).strong.compare_exchange_weak(current, current + 1usize,
                        core.sync.atomic.Ordering.Acquire, core.sync.atomic.Ordering.Relaxed) {
                    success(_) => { return present(Arc(self.p, b, allocator)) },
                    failure(seen) => { current = seen }
                }
            }
            none
        }
    }
    pub fn retain(): Weak<T, A> {
        let allocator = self.a.clone()
        if self.h != core.ptr.null_mut<ArcHeader>() {
            unsafe { increment_weak(self.h) }
        }
        Weak(self.p, self.h, allocator)
    }
    pub take fn into_raw(): RawWeak<T, A> {
        unsafe {
            let p = self.p
            let h = self.h
            let a = core.ptr.`read`(core.ptr.from_ref(self.a))
            core.mem.forget(take self)
            RawWeak(p, h, a)
        }
    }
}
extend<T: unsized, A: Allocator + Clone> Weak<T, A> implements Clone {
    fn clone(): Weak<T, A> { self.retain() }
}
pub unsafe fn weak_from_raw<T: unsized, A: Allocator>(take raw: RawWeak<T, A>): Weak<T, A> {
    // The raw token, including an empty null-header token, is reconstructed once.
    Weak(raw.p, raw.h, raw.a)
}
extend<T: unsized, A: Allocator> Arc<T, A> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get() }
}
extend<T: unsized, A: Allocator> Arc<T, A> implements AsRef<T> {
    fn as_ref(): read T from self { self.get() }
}
extend<T: unsized, A: Allocator> Arc<T, A> implements Borrow<T> {
    fn borrow(): read T from self { self.get() }
}
extend<T> Arc<T> implements From<T> {
    static fn from(take value: T): Arc<T> { new(value) }
}

extend<T: PartialEq + unsized, A: Allocator> Arc<T, A> implements PartialEq {
    fn eq(read other: Arc<T, A>): bool { self.get().eq(other.get()) }
}
extend<T: Eq + unsized, A: Allocator> Arc<T, A> implements Eq {}
extend<T: PartialOrd + unsized, A: Allocator> Arc<T, A> implements PartialOrd {
    fn partial_cmp(read other: Arc<T, A>): Ordering? {
        self.get().partial_cmp(other.get())
    }
}
extend<T: Ord + unsized, A: Allocator> Arc<T, A> implements Ord {
    fn cmp(read other: Arc<T, A>): Ordering { self.get().cmp(other.get()) }
}
extend<T: Hash + unsized, A: Allocator> Arc<T, A> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.get().hash(mut state) }
}
extend<T: fmt.Display + unsized, A: Allocator> Arc<T, A> implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Display).fmt(self.get(), mut f)
    }
}
extend<T: fmt.Debug + unsized, A: Allocator> Arc<T, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Debug).fmt(self.get(), mut f)
    }
}
extend<T: Error + unsized, A: Allocator> Arc<T, A> implements Error {
    fn source<region r>(
        receiver read self: Self from r
    ): (read any Error from r)? {
        T.(Error).source(self.get())
    }
}
extend<T: unsized, A: Allocator> Weak<T, A> {
    // The allocation remains alive while this weak owner exists, but its
    // payload may already have been destroyed; dereferencing is never valid
    // without first upgrading.
    pub fn as_ptr(): ptr<read T> { self.p.cast_const() }
    pub fn strong_count(): usize {
        if self.h == core.ptr.null_mut<ArcHeader>() { return 0usize }
        unsafe { (*self.h).strong.load(core.sync.atomic.Ordering.Acquire) }
    }
    pub fn weak_count(): usize {
        if self.h == core.ptr.null_mut<ArcHeader>() { return 0usize }
        unsafe {
            let strong = (*self.h).strong.load(core.sync.atomic.Ordering.Acquire)
            let weak_total = (*self.h).wk.load(core.sync.atomic.Ordering.Acquire)
            if weak_total == usize.MAX { return 0usize }
            if strong == 0usize || weak_total == 0usize { 0usize } else { weak_total - 1usize }
        }
    }
    pub fn ptr_eq(read other: Weak<T, A>): bool { self.h == other.h }
}

extend<T: Clone, A: Allocator + Clone> Arc<T, A> {
    pub mut fn make_mut(): mut T from self {
        if unsafe { is_unique(self.h) } { return unsafe { mut *self.p } }
        let replacement = new_uninit_in<T, A>(self.a.clone())
        let moved = unsafe {
            (*self.h).strong.compare_exchange(
                1usize, 0usize,
                core.sync.atomic.Ordering.Acquire, core.sync.atomic.Ordering.Relaxed
            ).is_success()
        }
        if moved {
            unsafe { core.ptr.write(replacement.p.cast<T>(), core.ptr.`read`(self.p)) }
            let initialized = unsafe { replacement.assume_init() }
            let old = unsafe { core.ptr.replace(core.ptr.from_mut(self), initialized) }
            let raw = old.into_raw()
            var allocator = raw.a
            let _implicit = WeakRelease(raw.h, core.ptr.from_mut(allocator))
        } else {
            let value = self.get().clone()
            unsafe { core.ptr.write(replacement.p.cast<T>(), value) }
            let initialized = unsafe { replacement.assume_init() }
            let _old = unsafe { core.ptr.replace(core.ptr.from_mut(self), initialized) }
        }
        unsafe { mut *self.p }
    }
}

extend<T: Default> Arc<T> implements Default {
    static fn default(): Arc<T> { new(T.(Default).default()) }
}
extend<T> Arc<[T]> implements Default {
    static fn default(): Arc<[T]> {
        unsafe { new_zeroed_slice<T>(0usize).assume_init() }
    }
}
extend Arc<Text> implements Default {
    static fn default(): Arc<Text> { copy_text("") }
}

// Shared owner whose payload never moves until the last owner destroys it.
// Only `pin` creates one: an existing `Arc` may have unpinned siblings that
// could still move the payload out. Owners reach the payload only by
// shared or pinned-read access.
pub type Pinned<T: unsized, A: Allocator = Global> {
    p: ptr<mut T>
    h: ptr<mut ArcHeader>
    a: A
    drop {
        unsafe {
            let b = self.h
            if (*b).strong.fetch_sub(1usize, core.sync.atomic.Ordering.Release) == 1usize {
                core.sync.atomic.fence(core.sync.atomic.Ordering.Acquire)
                let _implicit = WeakRelease(b, core.ptr.from_mut(self.a))
                core.ptr.drop_in_place(self.p)
            }
        }
    }
}

pub fn pin<T>(take value: T): Pinned<T> {
    let raw = new(value).into_raw()
    Pinned(raw.p, raw.h, raw.a)
}

extend<T: unsized, A: Allocator> Pinned<T, A> {
    pub fn as_ref(): pinned read T from self { unsafe { core.pin.Pin.new_unchecked(read *self.p) } }
    pub fn get_ref(): read T from self { unsafe { read *self.p } }
    pub fn ptr_eq(read other: Pinned<T, A>): bool { self.h == other.h }
}
extend<T: unsized, A: Allocator + Clone> Pinned<T, A> {
    // Another pinned owner of the same payload.
    pub fn retain(): Pinned<T, A> {
        let allocator = self.a.clone()
        unsafe { increment(core.ptr.from_mut((*self.h).strong)) }
        Pinned(self.p, self.h, allocator)
    }
}
extend<T: unsized, A: Allocator + Clone> Pinned<T, A> implements Clone {
    fn clone(): Pinned<T, A> { self.retain() }
}
extend<T: unsized, A: Allocator> Pinned<T, A> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get_ref() }
}
unsafe extend<T: unsized, A: Allocator> Pinned<T, A> implements Unpin {}
unsafe extend<T: Transferable + Shareable + unsized, A: Allocator + Transferable> Pinned<T, A> implements Transferable {}
unsafe extend<T: Transferable + Shareable + unsized, A: Allocator + Shareable> Pinned<T, A> implements Shareable {}
extend<T: Default> Pinned<T> implements Default {
    static fn default(): Pinned<T> { pin(T.(Default).default()) }
}
extend<T> Pinned<[T]> implements Default {
    static fn default(): Pinned<[T]> {
        let owner = unsafe { new_zeroed_slice<T>(0usize).assume_init() }
        let raw = owner.into_raw()
        Pinned(raw.p, raw.h, raw.a)
    }
}
extend Pinned<Text> implements Default {
    static fn default(): Pinned<Text> {
        let raw = copy_text("").into_raw()
        Pinned(raw.p, raw.h, raw.a)
    }
}

extend<T: unsized, A: Allocator> Weak<T, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str("(Weak)") }
}
extend<region r> Arc<Text> implements From<read Text from r> {
    static fn from(take value: read Text from r): Arc<Text> { copy_text(value) }
}
extend<region r> Arc<Text> implements From<mut Text from r> {
    static fn from(take value: mut Text from r): Arc<Text> { copy_text(read value) }
}
extend Arc<Text> implements From<super.string.String> {
    static fn from(take value: super.string.String): Arc<Text> { copy_text(value.as_text()) }
}
extend<T> Arc<T> implements From<super.boxed.Box<T>> {
    static fn from(take value: super.boxed.Box<T>): Arc<T> { new(value.into_inner()) }
}
extend<region r, T: Clone> Arc<[T]> implements From<read [T] from r> {
    static fn from(take values: read [T] from r): Arc<[T]> {
        var copies = super.vec.with_capacity<T>(values.len())
        var index = 0usize
        while index < values.len() {
            copies.push(values[index].clone())
            index += 1usize
        }
        Arc<[T]>.from(copies)
    }
}
extend<region r, T: Clone> Arc<[T]> implements From<mut [T] from r> {
    static fn from(take values: mut [T] from r): Arc<[T]> {
        var copies = super.vec.with_capacity<T>(values.len())
        var index = 0usize
        while index < values.len() {
            copies.push(values[index].clone())
            index += 1usize
        }
        Arc<[T]>.from(copies)
    }
}
extend<T> Arc<[T]> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(take items: I): Arc<[T]> {
        let values = super.vec.List<T>.(FromItems<T>).from_iter(items)
        Arc<[T]>.from(values)
    }
}
extend<T> Arc<[T]> implements From<super.vec.List<T>> {
    static fn from(take values: super.vec.List<T>): Arc<[T]> {
        var source = values
        let length = source.len()
        var owner = new_uninit_slice<T>(length)
        match take owner.get_mut() {
            present(slots) => {
                var index = length
                while index > 0usize {
                    index -= 1usize
                    slots[index] = core.mem.MaybeUninit<T>.new(source.pop().unwrap())
                }
            },
            none => {}
        }
        unsafe { owner.assume_init() }
    }
}
extend<T, const N: usize> Arc<[T]> implements From<[T; N]> {
    static fn from(take items: [T; N]): Arc<[T]> {
        let values = super.vec.List<T>.(From<[T; N]>).from(items)
        Arc<[T]>.(From<super.vec.List<T>>).from(values)
    }
}
extend<A: Allocator> Arc<[u8], A> implements From<Arc<Text, A>> {
    static fn from(take value: Arc<Text, A>): Arc<[u8], A> {
        let raw = value.into_raw()
        // Text is a byte-slice tail with byte-count metadata; ownership and allocation stay unchanged.
        let bytes = unsafe { core.mem.transmute<ptr<mut [u8]>>(raw.p) }
        Arc(bytes, raw.h, raw.a)
    }
}
extend<T, const N: usize, A: Allocator> Arc<[T; N], A> implements TryFrom<Arc<[T], A>> {
    type Error = Arc<[T], A>
    static fn try_from(take value: Arc<[T], A>): Outcome<Arc<[T; N], A>, Arc<[T], A>> {
        if value.get().len() != N { return failure(value) }
        let raw = value.into_raw()
        // The length check validates the array extent; payload and header allocation stay unchanged.
        success(Arc(raw.p.cast<[T; N]>(), raw.h, raw.a))
    }
}
