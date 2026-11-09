import package.core.iter.{FromItems, OwnedIterable}
import package.core.borrow.{AsRef, Borrow}
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.convert.From
import package.core.fmt
import package.core.hash.{Hash, Hasher}
import package.core.ops.Deref
import super.alloc.{Allocator, Global, AllocError, Layout, layout_of, layout_array, extend_layout, handle_alloc_error, layout_unchecked}
import package.core.clone.Clone
import package.core.default.Default
import package.core.text.Text
import super.vec.slice_ptr_mut

type RcHeader {
    strong: usize
    wk: usize
    allocation: Layout
}

// Non-empty raw handles own one strong or weak count and preserve slice or
// witness metadata. Empty weak tokens have a null header and own no count.
pub type RawRc<T: unsized, A: Allocator = Global> {
    p: ptr<mut T>
    h: ptr<mut RcHeader>
    a: A
}
pub type RawWeak<T: unsized, A: Allocator = Global> {
    p: ptr<mut T>
    h: ptr<mut RcHeader>
    a: A
}
extend<T: unsized, A: Allocator> RawRc<T, A> {
    pub fn as_ptr(): ptr<mut T> { self.p }
}
extend<T: unsized, A: Allocator> RawWeak<T, A> {
    pub fn as_ptr(): ptr<mut T> { self.p }
}

fn allocation_layout<T>(): (Layout, usize) throws AllocError {
    let result = capture extend_layout(layout_of<RcHeader>(), layout_of<T>())
    match take result {
        success(layout) => layout,
        failure(error) => throw AllocError(error.size, error.align)
    }
}

fn slice_allocation_layout<T>(len: usize): (Layout, usize, Layout) throws AllocError {
    let payload_result = capture layout_array<core.mem.MaybeUninit<T>>(len)
    let payload = match take payload_result {
        success(layout) => layout,
        failure(error) => throw AllocError(error.size, error.align)
    }
    let allocation_result = capture extend_layout(layout_of<RcHeader>(), payload)
    let (allocation, offset) = match take allocation_result {
        success(value) => value,
        failure(error) => throw AllocError(error.size, error.align)
    }
    (allocation, offset, payload)
}

// Single-threaded shared owner; the allocator travels with each handle.
pub type Rc<T: unsized, A: Allocator = Global> {
    p: ptr<mut T>
    h: ptr<mut RcHeader>
    a: A
    drop {
        unsafe {
            let b = self.h
            (*b).strong -= 1usize
            if (*b).strong == 0usize {
                let _implicit = WeakRelease(b, core.ptr.from_mut(self.a))
                core.ptr.drop_in_place(self.p)
            }
        }
    }
}

// Non-owning handle: keeps the block (not the payload) alive.
pub type Weak<T: unsized, A: Allocator = Global> {
    p: ptr<mut T>
    h: ptr<mut RcHeader>
    a: A
    drop {
        if self.h != core.ptr.null_mut<RcHeader>() {
            unsafe {
                let _guard = WeakRelease(self.h, core.ptr.from_mut(self.a))
            }
        }
    }
}

// Drops one weak reference and frees the block when none remain.
type WeakRelease<A: Allocator> {
    p: ptr<mut RcHeader>
    a: ptr<mut A>
    drop {
        unsafe {
            let b = self.p
            (*b).wk -= 1usize
            if (*b).wk == 0usize { (*self.a).deallocate(b.cast<u8>(), (*b).allocation) }
        }
    }
}

pub fn try_new_in<T, A: Allocator>(value: take T, allocator: take A): Rc<T, A> throws AllocError {
    var a = allocator
    let (layout, offset) = try allocation_layout<T>()
    let raw = try a.allocate(layout)
    let b = raw.cast<RcHeader>()
    let p = unsafe { raw.add(offset) }.cast<T>()
    unsafe {
        core.ptr.write(b, RcHeader(1usize, 1usize, layout))
        core.ptr.write(p, value)
    }
    Rc(p, b, a)
}
pub fn new_in<T, A: Allocator>(value: take T, allocator: take A): Rc<T, A> {
    let outcome = capture try_new_in(value, allocator)
    match take outcome {
        success(r) => r,
        failure(e) => handle_alloc_error(unsafe { layout_unchecked(e.size, e.align) })
    }
}
pub fn new<T>(value: take T): Rc<T> { new_in(value, Global()) }
pub fn try_new<T>(value: take T): Rc<T> throws AllocError { try try_new_in(value, Global()) }

// An empty Weak has no allocation or count; its null header is the sentinel.
pub fn new_weak<T>(): Weak<T> {
    Weak(core.ptr.null_mut<T>(), core.ptr.null_mut<RcHeader>(), Global())
}

extend<T> Weak<T> implements package.core.default.Default {
    static fn default(): Weak<T> { new_weak<T>() }
}

pub fn try_new_uninit_in<T, A: Allocator>(
    allocator: take A
): Rc<core.mem.MaybeUninit<T>, A> throws AllocError {
    try try_new_in(core.mem.MaybeUninit<T>.uninit(), allocator)
}
pub fn new_uninit_in<T, A: Allocator>(allocator: take A): Rc<core.mem.MaybeUninit<T>, A> {
    let result = capture try_new_uninit_in<T, A>(allocator)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}
pub fn try_new_uninit<T>(): Rc<core.mem.MaybeUninit<T>> throws AllocError {
    try try_new_uninit_in<T, Global>(Global())
}
pub fn new_uninit<T>(): Rc<core.mem.MaybeUninit<T>> { new_uninit_in<T, Global>(Global()) }

pub fn try_new_zeroed_in<T, A: Allocator>(
    allocator: take A
): Rc<core.mem.MaybeUninit<T>, A> throws AllocError {
    try try_new_in(core.mem.MaybeUninit<T>.zeroed(), allocator)
}
pub fn new_zeroed_in<T, A: Allocator>(allocator: take A): Rc<core.mem.MaybeUninit<T>, A> {
    let result = capture try_new_zeroed_in<T, A>(allocator)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}
pub fn try_new_zeroed<T>(): Rc<core.mem.MaybeUninit<T>> throws AllocError {
    try try_new_zeroed_in<T, Global>(Global())
}
pub fn new_zeroed<T>(): Rc<core.mem.MaybeUninit<T>> { new_zeroed_in<T, Global>(Global()) }

fn try_new_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A,
    zeroed: bool
): Rc<[core.mem.MaybeUninit<T>], A> throws AllocError {
    var a = allocator
    let (layout, offset, payload) = try slice_allocation_layout<T>(len)
    let raw = try a.allocate(layout)
    let h = raw.cast<RcHeader>()
    let data = unsafe { raw.add(offset) }.cast<core.mem.MaybeUninit<T>>()
    unsafe {
        core.ptr.write(h, RcHeader(1usize, 1usize, layout))
        if zeroed && payload.size() != 0usize {
            // Only the payload extent is zeroed; the reference-count header
            // remains initialized, and all payload slots remain MaybeUninit.
            core.ptr.write_bytes(data.cast<u8>(), 0u8, payload.size())
        }
    }
    Rc(slice_ptr_mut(data, len), h, a)
}

pub fn try_new_uninit_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Rc<[core.mem.MaybeUninit<T>], A> throws AllocError {
    try try_new_slice_in<T, A>(len, allocator, false)
}

pub fn new_uninit_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Rc<[core.mem.MaybeUninit<T>], A> {
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
): Rc<[core.mem.MaybeUninit<T>]> throws AllocError {
    try try_new_uninit_slice_in<T, Global>(len, Global())
}

pub fn new_uninit_slice<T>(len: usize): Rc<[core.mem.MaybeUninit<T>]> {
    new_uninit_slice_in<T, Global>(len, Global())
}

pub fn try_new_zeroed_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Rc<[core.mem.MaybeUninit<T>], A> throws AllocError {
    try try_new_slice_in<T, A>(len, allocator, true)
}

pub fn new_zeroed_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Rc<[core.mem.MaybeUninit<T>], A> {
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
): Rc<[core.mem.MaybeUninit<T>]> throws AllocError {
    try try_new_zeroed_slice_in<T, Global>(len, Global())
}

pub fn new_zeroed_slice<T>(len: usize): Rc<[core.mem.MaybeUninit<T>]> {
    new_zeroed_slice_in<T, Global>(len, Global())
}

// Copies only from a validated Text view, preserving Text's UTF-8 invariant.
pub fn try_copy_text_in<A: Allocator>(value: read Text, allocator: take A): Rc<Text, A> throws AllocError {
    var a = allocator
    let bytes = value.as_bytes()
    let result = capture extend_layout(layout_of<RcHeader>(), super.alloc.layout_of_val(bytes))
    let (layout, offset) = match take result {
        success(layout) => layout,
        failure(error) => throw AllocError(error.size, error.align)
    }
    let raw = try a.allocate(layout)
    let h = raw.cast<RcHeader>()
    let data = unsafe { raw.add(offset) }.cast<u8>()
    unsafe {
        core.ptr.write(h, RcHeader(1usize, 1usize, layout))
        core.ptr.copy(package.core.slice.data(bytes), data, bytes.len())
    }
    let slice = slice_ptr_mut(data, bytes.len())
    let text = unsafe { core.mem.transmute<ptr<mut Text>>(slice) }
    Rc(text, h, a)
}

pub fn copy_text_in<A: Allocator>(value: read Text, allocator: take A): Rc<Text, A> {
    let outcome = capture try_copy_text_in(value, allocator)
    match take outcome {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}

pub fn try_copy_text(value: read Text): Rc<Text> throws AllocError {
    try try_copy_text_in(value, Global())
}
pub fn copy_text(value: read Text): Rc<Text> { copy_text_in(value, Global()) }

fn bump(count: usize): usize {
    // Overflow would let a count wrap to zero and free a live payload.
    if count == 0xffffffffffffffffusize { core.intrinsics.abort() }
    count + 1usize
}

pub fn try_new_cyclic_in<T, A: Allocator + Clone, F: take fn(read Weak<T, A>): T>(
    allocator: take A,
    make: take F
): Rc<T, A> throws AllocError {
    var a = allocator
    let weak_allocator = a.clone()
    let (layout, offset) = try allocation_layout<T>()
    let raw = try a.allocate(layout)
    let h = raw.cast<RcHeader>()
    let p = unsafe { raw.add(offset) }.cast<T>()
    // Keep upgrades disabled until the payload is initialized; the guard
    // releases the implicit weak count if the constructor unwinds.
    unsafe { core.ptr.write(h, RcHeader(0usize, 2usize, layout)) }
    let weak_handle = Weak(p, h, weak_allocator)
    let _guard = WeakRelease(h, core.ptr.from_mut(a))
    let value = make(read weak_handle)
    unsafe {
        core.ptr.write(p, value)
        (*h).strong = 1usize
    }
    core.mem.forget(take _guard)
    Rc(p, h, a)
}
pub fn new_cyclic_in<T, A: Allocator + Clone, F: take fn(read Weak<T, A>): T>(
    allocator: take A,
    make: take F
): Rc<T, A> {
    let result = capture try_new_cyclic_in<T, A, F>(allocator, make)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}
pub fn try_new_cyclic<T, F: take fn(read Weak<T>): T>(make: take F): Rc<T> throws AllocError {
    try try_new_cyclic_in<T, Global, F>(Global(), make)
}
pub fn new_cyclic<T, F: take fn(read Weak<T>): T>(make: take F): Rc<T> {
    new_cyclic_in<T, Global, F>(Global(), make)
}

extend<T: unsized, A: Allocator + Clone> Rc<T, A> {
    // Another strong owner of the same payload; the payload is not cloned.
    pub fn retain(): Rc<T, A> {
        let allocator = self.a.clone()
        unsafe { (*self.h).strong = bump((*self.h).strong) }
        Rc(self.p, self.h, allocator)
    }
    pub fn downgrade(): Weak<T, A> {
        let allocator = self.a.clone()
        unsafe { (*self.h).wk = bump((*self.h).wk) }
        Weak(self.p, self.h, allocator)
    }
}
extend<T: unsized, A: Allocator + Clone> Rc<T, A> implements Clone {
    fn clone(): Rc<T, A> { self.retain() }
}

extend<T, A: Allocator> Rc<core.mem.MaybeUninit<T>, A> {
    // Safety: the caller initialized the payload before taking ownership as T.
    pub take unsafe fn assume_init(): Rc<T, A> {
        let raw = self.into_raw()
        unsafe { from_raw(RawRc(raw.p.cast<T>(), raw.h, raw.a)) }
    }
}

extend<T, A: Allocator> Rc<[core.mem.MaybeUninit<T>], A> {
    // Safety: every element is initialized as T; element layout and length
    // metadata are unchanged by replacing MaybeUninit<T> with T.
    pub take unsafe fn assume_init(): Rc<[T], A> {
        let raw = self.into_raw()
        let slice = unsafe { core.mem.transmute<ptr<mut [T]>>(raw.p) }
        unsafe { from_raw(RawRc(slice, raw.h, raw.a)) }
    }
}

extend<T: unsized, A: Allocator> Rc<T, A> {
    pub fn get(): read T from self { unsafe { read *self.p } }
    // The pointer is valid while this strong owner remains alive.
    pub fn as_ptr(): ptr<read T> { self.p.cast_const() }
    pub fn strong_count(): usize { unsafe { (*self.h).strong } }
    pub fn weak_count(): usize { unsafe { (*self.h).wk - 1usize } }
    pub fn ptr_eq(other: read Rc<T, A>): bool { self.h == other.h }
    pub fn is_unique(): bool { unsafe { (*self.h).strong == 1usize && (*self.h).wk == 1usize } }
    // Exclusive access only while no other strong or weak handle exists.
    pub mut fn get_mut(): (mut T from self)? {
        if self.is_unique() { present(unsafe { mut *self.p }) } else { none }
    }
}

extend<T, A: Allocator> Rc<T, A> {
    // Moves the payload out when this is the only strong owner; otherwise the
    // handle is returned unchanged. Weak handles may remain but can no longer
    // upgrade.
    pub take fn try_unwrap(): T throws Rc<T, A> {
        if unsafe { (*self.h).strong } != 1usize { throw self }
        unsafe {
            let b = self.h
            let value = core.ptr.`read`(self.p)
            (*b).strong = 0usize
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

extend<T: unsized, A: Allocator> Rc<T, A> {
    pub take fn into_raw(): RawRc<T, A> {
        unsafe {
            let p = self.p
            let h = self.h
            let a = core.ptr.`read`(core.ptr.from_ref(self.a))
            core.mem.forget(take self)
            RawRc(p, h, a)
        }
    }
}
pub unsafe fn from_raw<T: unsized, A: Allocator>(raw: take RawRc<T, A>): Rc<T, A> {
    Rc(raw.p, raw.h, raw.a)
}
// Creates a second raw ownership token; consume both tokens exactly once.
pub unsafe fn increment_strong_count<T: unsized, A: Allocator + Clone>(
    raw: read RawRc<T, A>
): RawRc<T, A> {
    let allocator = raw.a.clone()
    unsafe { (*raw.h).strong = bump((*raw.h).strong) }
    RawRc(raw.p, raw.h, allocator)
}
pub unsafe fn decrement_strong_count<T: unsized, A: Allocator>(raw: take RawRc<T, A>): Unit {
    let _owner = unsafe { from_raw(raw) }
}

extend<T: unsized, A: Allocator + Clone> Weak<T, A> {
    pub fn upgrade(): Rc<T, A>? {
        if self.h == core.ptr.null_mut<RcHeader>() { return none }
        unsafe {
            let b = self.h
            if (*b).strong == 0usize { return none }
            (*b).strong = bump((*b).strong)
            present(Rc(self.p, b, self.a.clone()))
        }
    }
    pub fn retain(): Weak<T, A> {
        let allocator = self.a.clone()
        if self.h != core.ptr.null_mut<RcHeader>() {
            unsafe { (*self.h).wk = bump((*self.h).wk) }
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
pub unsafe fn weak_from_raw<T: unsized, A: Allocator>(raw: take RawWeak<T, A>): Weak<T, A> {
    // The raw token, including an empty null-header token, is reconstructed once.
    Weak(raw.p, raw.h, raw.a)
}
extend<T: unsized, A: Allocator> Weak<T, A> {
    // This pointer may dangle after the payload is dropped; upgrade before
    // dereferencing it.
    pub fn as_ptr(): ptr<read T> { self.p.cast_const() }
    pub fn strong_count(): usize {
        if self.h == core.ptr.null_mut<RcHeader>() { return 0usize }
        unsafe { (*self.h).strong }
    }
    pub fn weak_count(): usize {
        if self.h == core.ptr.null_mut<RcHeader>() { return 0usize }
        unsafe {
            if (*self.h).strong == 0usize {
                0usize
            } else {
                (*self.h).wk - 1usize
            }
        }
    }
    pub fn ptr_eq(other: read Weak<T, A>): bool { self.h == other.h }
}

extend<T: Clone, A: Allocator + Clone> Rc<T, A> {
    pub mut fn make_mut(): mut T from self {
        if self.is_unique() { return unsafe { mut *self.p } }
        let replacement = new_in(self.get().clone(), self.a.clone())
        let _old = unsafe { core.ptr.replace(core.ptr.from_mut(self), replacement) }
        unsafe { mut *self.p }
    }
}

extend<T: Default> Rc<T> implements Default {
    static fn default(): Rc<T> { new(T.(Default).default()) }
}
extend<T> Rc<[T]> implements Default {
    static fn default(): Rc<[T]> {
        unsafe { new_zeroed_slice<T>(0usize).assume_init() }
    }
}
extend Rc<Text> implements Default {
    static fn default(): Rc<Text> { copy_text("") }
}

extend<T, A: Allocator> Rc<[T], A> implements From<super.vec.List<T, A>> {
    static fn from(values: take super.vec.List<T, A>): Rc<[T], A> {
        let source = values.into_boxed_slice()
        let length = source.get().len()
        let source_layout = super.alloc.layout_of_val(source.get())
        let raw = source.into_raw()
        let source_items = raw.0.cast<T>()
        var allocator = raw.1

        let layout_result = capture slice_allocation_layout<T>(length)
        let (allocation_layout, offset, _) = match take layout_result {
            success(layout) => layout,
            failure(error) => {
                handle_alloc_error(unsafe {
                    layout_unchecked(error.size, error.align)
                })
            }
        }
        let allocation = match capture allocator.allocate(allocation_layout) {
            success(pointer) => pointer,
            failure(_) => handle_alloc_error(allocation_layout)
        }
        // The helper places the header and the length-sized, aligned payload
        // inside this exact allocation before any pointer arithmetic occurs.
        let header = allocation.cast<RcHeader>()
        let destination = unsafe { allocation.add(offset) }.cast<core.mem.MaybeUninit<T>>()
        unsafe { core.ptr.write(header, RcHeader(1usize, 1usize, allocation_layout)) }

        var index = 0usize
        while index < length {
            // The consumed Box owns exactly `length` initialized source items;
            // each is moved once into a distinct in-bounds uninitialized slot.
            unsafe {
                let item = core.ptr.`read`(source_items.add(index))
                core.ptr.write(
                    destination.add(index),
                    core.mem.MaybeUninit<T>.new(item)
                )
            }
            index += 1usize
        }
        let slice = slice_ptr_mut(destination.cast<T>(), length)
        var owner = Rc(slice, header, allocator)
        // The source is moved-from and its captured dynamic layout remains
        // paired with the same allocator value now owned by `owner`.
        let _release_source = unsafe {
            super.alloc.free_block(
                source_items.cast<u8>(),
                source_layout,
                core.ptr.from_mut(owner.a)
            )
        }
        core.mem.drop(take _release_source)
        owner
    }
}

// Shared handles compare, hash and format as their payload; `ptr_eq` tests identity.
extend<T: unsized, A: Allocator> Rc<T, A> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get() }
}
extend<T: unsized, A: Allocator> Rc<T, A> implements AsRef<T> {
    fn as_ref(): read T from self { self.get() }
}
extend<T: unsized, A: Allocator> Rc<T, A> implements Borrow<T> {
    fn borrow(): read T from self { self.get() }
}
extend<T> Rc<T> implements From<T> {
    static fn from(value: take T): Rc<T> { new(value) }
}
extend<T: PartialEq + unsized, A: Allocator> Rc<T, A> implements PartialEq {
    fn eq(other: read Rc<T, A>): bool { self.get().eq(other.get()) }
}
extend<T: Eq + unsized, A: Allocator> Rc<T, A> implements Eq {}
extend<T: PartialOrd + unsized, A: Allocator> Rc<T, A> implements PartialOrd {
    fn partial_cmp(other: read Rc<T, A>): Ordering? { self.get().partial_cmp(other.get()) }
}
extend<T: Ord + unsized, A: Allocator> Rc<T, A> implements Ord {
    fn cmp(other: read Rc<T, A>): Ordering { self.get().cmp(other.get()) }
}
extend<T: Hash + unsized, A: Allocator> Rc<T, A> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.get().hash(mut state) }
}
extend<T: fmt.Display + unsized, A: Allocator> Rc<T, A> implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try T.(fmt.Display).fmt(self.get(), mut f) }
}
extend<T: fmt.Debug + unsized, A: Allocator> Rc<T, A> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try T.(fmt.Debug).fmt(self.get(), mut f) }
}

// Shared owner whose payload never moves until the last owner destroys it.
// Only `pin` creates one: an existing `Rc` may have unpinned siblings that
// could still move the payload out. Owners reach the payload only by
// shared or pinned-read access.
pub type Pinned<T: unsized, A: Allocator = Global> {
    p: ptr<mut T>
    h: ptr<mut RcHeader>
    a: A
    drop {
        unsafe {
            let b = self.h
            (*b).strong -= 1usize
            if (*b).strong == 0usize {
                let _implicit = WeakRelease(b, core.ptr.from_mut(self.a))
                core.ptr.drop_in_place(self.p)
            }
        }
    }
}

pub fn pin<T>(value: take T): Pinned<T> {
    let raw = new(value).into_raw()
    Pinned(raw.p, raw.h, raw.a)
}

extend<T: unsized, A: Allocator> Pinned<T, A> {
    pub fn as_ref(): pinned read T from self { unsafe { core.pin.Pin.new_unchecked(read *self.p) } }
    pub fn get_ref(): read T from self { unsafe { read *self.p } }
    pub fn ptr_eq(other: read Pinned<T, A>): bool { self.h == other.h }
}
extend<T: unsized, A: Allocator + Clone> Pinned<T, A> {
    // Another pinned owner of the same payload.
    pub fn retain(): Pinned<T, A> {
        let allocator = self.a.clone()
        unsafe { (*self.h).strong = bump((*self.h).strong) }
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
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try f.write_str("(Weak)") }
}
extend Rc<Text> implements From<read Text> {
    static fn from(value: read Text): Rc<Text> { copy_text(value) }
}
extend Rc<Text> implements From<super.string.String> {
    static fn from(value: take super.string.String): Rc<Text> { copy_text(value.as_text()) }
}
extend<T> Rc<T> implements From<super.boxed.Box<T>> {
    static fn from(value: take super.boxed.Box<T>): Rc<T> { new(value.into_inner()) }
}
extend<T: Clone> Rc<[T]> implements From<read [T]> {
    static fn from(values: read [T]): Rc<[T]> {
        var copies = super.vec.with_capacity<T>(values.len())
        var index = 0usize
        while index < values.len() {
            copies.push(values[index].clone())
            index += 1usize
        }
        Rc<[T]>.from(copies)
    }
}
extend<T> Rc<[T]> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(items: take I): Rc<[T]> {
        let values = super.vec.List<T>.(FromItems<T>).from_iter(items)
        Rc<[T]>.from(values)
    }
}
