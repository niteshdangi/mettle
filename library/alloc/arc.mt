// Atomically reference-counted shared owner. Counting is atomic; that makes
// the handles themselves thread-safe, not the payload: an `Arc<T>` crosses or
// is shared between threads only when `T` is both Transferable and Shareable.
import super.alloc.{Allocator, Global, AllocError, Layout, layout_of, extend_layout, handle_alloc_error, layout_unchecked}
import package.core.clone.Clone
import package.core.borrow.{AsRef, Borrow}
import package.core.default.Default
import package.core.convert.{From, TryFrom}
import package.core.iter.{OwnedIterable, FromItems}
import package.core.ops.Deref
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.hash.{Hash, Hasher}
import package.core.error.Error
import package.core.text.Text
import super.vec.slice_ptr_mut

type ArcHeader {
    strong: core.sync.atomic.AtomicUsize
    wk: core.sync.atomic.AtomicUsize
    allocation: Layout
}

// Raw handles are ownership tokens carrying both the payload and count header.
// Reconstruct each token exactly once with the matching from_raw function.
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
        success(layout) => layout,
        failure(error) => throw AllocError(error.size, error.align)
    }
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

// Non-owning handle: keeps the block (not the payload) alive. A null header
// marks an empty weak handle; its aligned payload pointer is never dereferenced.
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

pub fn try_new_in<T, A: Allocator>(value: take T, allocator: take A): Arc<T, A> throws AllocError {
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
pub fn new_in<T, A: Allocator>(value: take T, allocator: take A): Arc<T, A> {
    let outcome = capture try_new_in(value, allocator)
    match take outcome {
        success(r) => r,
        failure(e) => handle_alloc_error(unsafe { layout_unchecked(e.size, e.align) })
    }
}
pub fn new<T>(value: take T): Arc<T> { new_in(value, Global()) }
pub fn try_new<T>(value: take T): Arc<T> throws AllocError { try try_new_in(value, Global()) }

pub fn try_new_uninit_in<T, A: Allocator>(
    allocator: take A
): Arc<core.mem.MaybeUninit<T>, A> throws AllocError {
    try try_new_in(core.mem.MaybeUninit<T>.uninit(), allocator)
}
pub fn new_uninit_in<T, A: Allocator>(
    allocator: take A
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
    allocator: take A
): Arc<core.mem.MaybeUninit<T>, A> throws AllocError {
    try try_new_in(core.mem.MaybeUninit<T>.zeroed(), allocator)
}
pub fn new_zeroed_in<T, A: Allocator>(
    allocator: take A
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

fn fill_arc_slice<T, A: Allocator>(
    len: usize,
    allocator: take A,
    zeroed: bool
): Arc<[core.mem.MaybeUninit<T>], A> throws AllocError {
    var a = allocator
    let size = core.mem.size_of<core.mem.MaybeUninit<T>>()
    let align = core.mem.align_of<core.mem.MaybeUninit<T>>()
    let bytes = if len == 0usize || size == 0usize {
        0usize
    } else {
        match len.checked_mul(size) {
            present(value) => value,
            none => throw AllocError(0xffffffffffffffffusize, align)
        }
    }
    let payload = unsafe { layout_unchecked(bytes, align) }
    let laid_out = capture extend_layout(layout_of<ArcHeader>(), payload)
    let (layout, offset) = match take laid_out {
        success(value) => value,
        failure(error) => throw AllocError(error.size, error.align)
    }
    let raw = try a.allocate(layout)
    let header = raw.cast<ArcHeader>()
    let data = unsafe { raw.add(offset) }.cast<core.mem.MaybeUninit<T>>()
    unsafe {
        core.ptr.write(header, ArcHeader(core.sync.atomic.AtomicUsize.new(1usize),
                                          core.sync.atomic.AtomicUsize.new(1usize),
                                          layout))
    }
    if size != 0usize {
        var index = 0usize
        while index < len {
            let slot = if zeroed {
                core.mem.MaybeUninit<T>.zeroed()
            } else {
                core.mem.MaybeUninit<T>.uninit()
            }
            unsafe { core.ptr.write(data.add(index), slot) }
            index += 1usize
        }
    }
    Arc(slice_ptr_mut(data, len), header, a)
}

pub fn try_new_uninit_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Arc<[core.mem.MaybeUninit<T>], A> throws AllocError {
    try fill_arc_slice<T, A>(len, allocator, false)
}
pub fn new_uninit_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Arc<[core.mem.MaybeUninit<T>], A> {
    let result = capture try_new_uninit_slice_in<T, A>(len, allocator)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}
pub fn try_new_uninit_slice<T>(len: usize): Arc<[core.mem.MaybeUninit<T>]> throws AllocError {
    try try_new_uninit_slice_in<T, Global>(len, Global())
}
pub fn new_uninit_slice<T>(len: usize): Arc<[core.mem.MaybeUninit<T>]> {
    new_uninit_slice_in<T, Global>(len, Global())
}
pub fn try_new_zeroed_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Arc<[core.mem.MaybeUninit<T>], A> throws AllocError {
    try fill_arc_slice<T, A>(len, allocator, true)
}
pub fn new_zeroed_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Arc<[core.mem.MaybeUninit<T>], A> {
    let result = capture try_new_zeroed_slice_in<T, A>(len, allocator)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}
pub fn try_new_zeroed_slice<T>(len: usize): Arc<[core.mem.MaybeUninit<T>]> throws AllocError {
    try try_new_zeroed_slice_in<T, Global>(len, Global())
}
pub fn new_zeroed_slice<T>(len: usize): Arc<[core.mem.MaybeUninit<T>]> {
    new_zeroed_slice_in<T, Global>(len, Global())
}

extend<T> Arc<T> {
    pub static fn new_uninit_slice(len: usize): Arc<[core.mem.MaybeUninit<T>]> {
        new_uninit_slice_in<T, Global>(len, Global())
    }
    pub static fn new_zeroed_slice(len: usize): Arc<[core.mem.MaybeUninit<T>]> {
        new_zeroed_slice_in<T, Global>(len, Global())
    }
}

// Copies only from a validated Text view, preserving Text's UTF-8 invariant.
pub fn try_copy_text_in<A: Allocator>(value: read Text, allocator: take A): Arc<Text, A> throws AllocError {
    var a = allocator
    let bytes = value.as_bytes()
    let result = capture extend_layout(layout_of<ArcHeader>(), super.alloc.layout_of_val(bytes))
    let (layout, offset) = match take result {
        success(layout) => layout,
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

pub fn copy_text_in<A: Allocator>(value: read Text, allocator: take A): Arc<Text, A> {
    let outcome = capture try_copy_text_in(value, allocator)
    match take outcome {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}

pub fn try_copy_text(value: read Text): Arc<Text> throws AllocError {
    try try_copy_text_in(value, Global())
}
pub fn copy_text(value: read Text): Arc<Text> { copy_text_in(value, Global()) }

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

pub fn try_new_cyclic_in<T, A: Allocator + Clone, F: take fn(read Weak<T, A>): T>(
    allocator: take A,
    make: take F
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
    allocator: take A,
    make: take F
): Arc<T, A> {
    let result = capture try_new_cyclic_in<T, A, F>(allocator, make)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}
pub fn try_new_cyclic<T, F: take fn(read Weak<T>): T>(make: take F): Arc<T> throws AllocError {
    try try_new_cyclic_in<T, Global, F>(Global(), make)
}
pub fn new_cyclic<T, F: take fn(read Weak<T>): T>(make: take F): Arc<T> {
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
        unsafe { increment(core.ptr.from_mut((*self.h).wk)) }
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
    // Safety: every element was initialized before taking ownership as [T].
    pub take unsafe fn assume_init(): Arc<[T], A> {
        let raw = self.into_raw()
        let payload = unsafe { core.mem.transmute<ptr<mut [T]>>(raw.p) }
        unsafe { from_raw(RawArc(payload, raw.h, raw.a)) }
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
            if strong == 0usize || weak_total == 0usize { weak_total } else { weak_total - 1usize }
        }
    }
    pub fn ptr_eq(other: read Arc<T, A>): bool { self.h == other.h }
    // Exclusive access only while no other strong or weak handle exists. A
    // weak handle can only be created through a strong one, so when this
    // handle is the sole owner nothing can race with the check.
    pub mut fn get_mut(): (mut T from self)? {
        unsafe {
            let b = self.h
            let unique = (*b).wk.load(core.sync.atomic.Ordering.Acquire) == 1usize &&
                         (*b).strong.load(core.sync.atomic.Ordering.Acquire) == 1usize
            if unique { present(mut *self.p) } else { none }
        }
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
        let outcome = capture self.try_unwrap()
        match take outcome {
            success(v) => present(v),
            failure(rc) => none
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
pub unsafe fn from_raw<T: unsized, A: Allocator>(raw: take RawArc<T, A>): Arc<T, A> {
    Arc(raw.p, raw.h, raw.a)
}
// Creates a second raw ownership token; consume both tokens exactly once.
pub unsafe fn increment_strong_count<T: unsized, A: Allocator + Clone>(
    raw: read RawArc<T, A>
): RawArc<T, A> {
    let allocator = raw.a.clone()
    unsafe { increment(core.ptr.from_mut((*raw.h).strong)) }
    RawArc(raw.p, raw.h, allocator)
}
pub unsafe fn decrement_strong_count<T: unsized, A: Allocator>(raw: take RawArc<T, A>): Unit {
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
        if self.h == core.ptr.null_mut<ArcHeader>() { return Weak(self.p, self.h, allocator) }
        unsafe { increment(core.ptr.from_mut((*self.h).wk)) }
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

// An empty weak handle owns no allocation and can never be upgraded.
extend<T> Weak<T> {
    pub static fn new(): Weak<T> {
        Weak(super.alloc.dangling_for<T>(), core.ptr.null_mut<ArcHeader>(), Global())
    }
}

pub unsafe fn weak_from_raw<T: unsized, A: Allocator>(raw: take RawWeak<T, A>): Weak<T, A> {
    Weak(raw.p, raw.h, raw.a)
}
extend<A: Allocator> Arc<any core.any.Any, A> {
    // Recovers the concrete owner when the erased payload is a `T`; otherwise
    // the handle is returned unchanged.
    pub take fn downcast<T>(): Arc<T, A> throws Arc<any core.any.Any, A> {
        if !core.any.is<T>(self.get()) { throw self }
        let raw = self.into_raw()
        unsafe { from_raw(RawArc(raw.p.cast<T>(), raw.h, raw.a)) }
    }
}

extend<T: unsized, A: Allocator> Arc<T, A> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get() }
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
            if strong == 0usize || weak_total == 0usize { weak_total } else { weak_total - 1usize }
        }
    }
    pub fn ptr_eq(other: read Weak<T, A>): bool { self.h == other.h }
}

extend<T: Clone, A: Allocator + Clone> Arc<T, A> {
    pub mut fn make_mut(): mut T from self {
        let unique = unsafe {
            (*self.h).wk.load(core.sync.atomic.Ordering.Acquire) == 1usize &&
            (*self.h).strong.load(core.sync.atomic.Ordering.Acquire) == 1usize
        }
        if unique { return unsafe { mut *self.p } }
        let replacement = new_in(self.get().clone(), self.a.clone())
        let _old = unsafe { core.ptr.replace(core.ptr.from_mut(self), replacement) }
        unsafe { mut *self.p }
    }
}

extend<T: unsized, A: Allocator> Arc<T, A> implements AsRef<T> {
    fn as_ref(): read T from self { self.get() }
}
extend<T: unsized, A: Allocator> Arc<T, A> implements Borrow<T> {
    fn borrow(): read T from self { self.get() }
}
extend<T: Default, A: Allocator + Default> Arc<T, A> implements Default {
    static fn default(): Arc<T, A> { new_in(T.(Default).default(), A.(Default).default()) }
}
extend<T> Weak<T> implements Default {
    static fn default(): Weak<T> { Weak<T>.new() }
}
extend<T> Arc<T> implements From<T> {
    static fn `from`(value: take T): Arc<T> { new(value) }
}

extend<T: PartialEq, A: Allocator> Arc<T, A> implements PartialEq {
    fn eq(other: read Arc<T, A>): bool { self.get().eq(other.get()) }
}
extend<T: Eq, A: Allocator> Arc<T, A> implements Eq {}
extend<T: PartialOrd, A: Allocator> Arc<T, A> implements PartialOrd {
    fn partial_cmp(other: read Arc<T, A>): Ordering? { self.get().partial_cmp(other.get()) }
}
extend<T: Ord, A: Allocator> Arc<T, A> implements Ord {
    fn cmp(other: read Arc<T, A>): Ordering { self.get().cmp(other.get()) }
}
extend<T: Hash, A: Allocator> Arc<T, A> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.get().hash(mut state) }
}
extend<T: fmt.Display, A: Allocator> Arc<T, A> implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Display).fmt(self.get(), mut f)
    }
}
extend<T: fmt.Debug, A: Allocator> Arc<T, A> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Debug).fmt(self.get(), mut f)
    }
}
extend<T: Error, A: Allocator> Arc<T, A> implements Error {
    fn source<region r>(receiver self: read Arc<T, A> from r): (read any Error from r)? {
        T.(Error).source(self.get())
    }
}
extend<T: fmt.Debug, A: Allocator> Weak<T, A> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try f.write_str("Weak") }
}

// Moves the elements of `items` into one shared slice allocation.
fn from_list<T>(items: take super.vec.List<T>): Arc<[T]> {
    var items = items
    let len = items.len()
    let target = new_uninit_slice<T>(len)
    unsafe {
        core.ptr.copy(items.as_ptr(), target.p.cast<T>(), len)
        items.set_len(0usize)
        target.assume_init()
    }
}
extend<T> Arc<[T]> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(items: take I): Arc<[T]> {
        let collected: super.vec.List<T> = core.iter.collect(items)
        from_list(collected)
    }
}
extend<T, const N: usize> Arc<[T]> implements From<[T; N]> {
    static fn `from`(value: take [T; N]): Arc<[T]> { from_list(super.vec.from_array(value)) }
}
// Fails with the original owner when the length differs from `N`.
extend<T, A: Allocator, const N: usize> Arc<[T; N], A> implements TryFrom<Arc<[T], A>> {
    type Error = Arc<[T], A>
    static fn try_from(value: take Arc<[T], A>): (Arc<[T; N], A> throws Arc<[T], A>) {
        if value.get().len() != N { return failure(value) }
        let raw = value.into_raw()
        success(unsafe { from_raw(RawArc(raw.p.cast<[T; N]>(), raw.h, raw.a)) })
    }
}
