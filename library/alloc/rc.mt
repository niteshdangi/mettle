import core.iter.{FromItems, OwnedIterable}
import core.borrow.{AsRef, Borrow}
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.convert.{From, TryFrom}
import core.fmt
import core.hash.{Hash, Hasher}
import core.ops.Deref
import super.alloc.{Allocator, Global, AllocError, Layout, layout_of, layout_array, extend_layout, handle_alloc_error, layout_unchecked}
import core.clone.Clone
import core.default.Default
import core.text.Text
import core.any.Any
import super.vec.slice_ptr_mut

type LocalSharedHeader {
    strong: usize
    wk: usize
    allocation: Layout
}

// Non-empty raw handles own one strong or weak count and preserve slice or
// witness metadata. Empty weak tokens have a null header and own no count.
pub type RawLocalShared<T: unsized, A: Allocator = Global> {
    p: ptr<mut T>
    h: ptr<mut LocalSharedHeader>
    a: A
}
pub type RawWeak<T: unsized, A: Allocator = Global> {
    p: ptr<mut T>
    h: ptr<mut LocalSharedHeader>
    a: A
}
extend<T: unsized, A: Allocator> RawLocalShared<T, A> {
    pub fn as_ptr(): ptr<mut T> { self.p }
}
extend<T: unsized, A: Allocator> RawWeak<T, A> {
    pub fn as_ptr(): ptr<mut T> { self.p }
}

fn allocation_layout<T>(): (Layout, usize) throws AllocError {
    let result = capture extend_layout(layout_of<LocalSharedHeader>(), layout_of<T>())
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
    let allocation_result = capture extend_layout(layout_of<LocalSharedHeader>(), payload)
    let (allocation, offset) = match take allocation_result {
        success((layout, offset)) => (layout.pad_to_align(), offset),
        failure(error) => throw AllocError(error.size, error.align)
    }
    (allocation, offset, payload)
}

// Single-threaded shared owner; the allocator travels with each handle.
pub type LocalShared<T: unsized, A: Allocator = Global> {
    p: ptr<mut T>
    h: ptr<mut LocalSharedHeader>
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
    h: ptr<mut LocalSharedHeader>
    a: A
    drop {
        if self.h != core.ptr.null_mut<LocalSharedHeader>() {
            unsafe {
                let _guard = WeakRelease(self.h, core.ptr.from_mut(self.a))
            }
        }
    }
}

// Drops one weak reference and frees the block when none remain.
type WeakRelease<A: Allocator> {
    p: ptr<mut LocalSharedHeader>
    a: ptr<mut A>
    drop {
        unsafe {
            let b = self.p
            (*b).wk -= 1usize
            if (*b).wk == 0usize { (*self.a).deallocate(b.cast<u8>(), (*b).allocation) }
        }
    }
}

pub fn try_new_in<T, A: Allocator>(take value: T, take allocator: A): LocalShared<T, A> throws AllocError {
    var a = allocator
    let (layout, offset) = try allocation_layout<T>()
    let raw = try a.allocate(layout)
    let b = raw.cast<LocalSharedHeader>()
    let p = unsafe { raw.add(offset) }.cast<T>()
    unsafe {
        core.ptr.write(b, LocalSharedHeader(1usize, 1usize, layout))
        core.ptr.write(p, value)
    }
    LocalShared(p, b, a)
}
pub fn new_in<T, A: Allocator>(take value: T, take allocator: A): LocalShared<T, A> {
    let outcome = capture try_new_in(value, allocator)
    match take outcome {
        success(r) => r,
        failure(e) => handle_alloc_error(unsafe { layout_unchecked(e.size, e.align) })
    }
}
pub fn new<T>(take value: T): LocalShared<T> { new_in(value, Global()) }
pub fn try_new<T>(take value: T): LocalShared<T> throws AllocError { try try_new_in(value, Global()) }

// An empty Weak has no allocation or count; its null header is the sentinel.
pub fn new_weak<T>(): Weak<T> {
    Weak(core.ptr.null_mut<T>(), core.ptr.null_mut<LocalSharedHeader>(), Global())
}

extend<T> Weak<T> implements core.default.Default {
    static fn default(): Weak<T> { new_weak<T>() }
}

pub fn try_new_uninit_in<T, A: Allocator>(
    take allocator: A
): LocalShared<core.mem.MaybeUninit<T>, A> throws AllocError {
    try try_new_in(core.mem.MaybeUninit<T>.uninit(), allocator)
}
pub fn new_uninit_in<T, A: Allocator>(take allocator: A): LocalShared<core.mem.MaybeUninit<T>, A> {
    let result = capture try_new_uninit_in<T, A>(allocator)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}
pub fn try_new_uninit<T>(): LocalShared<core.mem.MaybeUninit<T>> throws AllocError {
    try try_new_uninit_in<T, Global>(Global())
}
pub fn new_uninit<T>(): LocalShared<core.mem.MaybeUninit<T>> { new_uninit_in<T, Global>(Global()) }

pub fn try_new_zeroed_in<T, A: Allocator>(
    take allocator: A
): LocalShared<core.mem.MaybeUninit<T>, A> throws AllocError {
    try try_new_in(core.mem.MaybeUninit<T>.zeroed(), allocator)
}
pub fn new_zeroed_in<T, A: Allocator>(take allocator: A): LocalShared<core.mem.MaybeUninit<T>, A> {
    let result = capture try_new_zeroed_in<T, A>(allocator)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}
pub fn try_new_zeroed<T>(): LocalShared<core.mem.MaybeUninit<T>> throws AllocError {
    try try_new_zeroed_in<T, Global>(Global())
}
pub fn new_zeroed<T>(): LocalShared<core.mem.MaybeUninit<T>> { new_zeroed_in<T, Global>(Global()) }

fn try_new_slice_in<T, A: Allocator>(
    len: usize,
    take allocator: A,
    zeroed: bool
): LocalShared<[core.mem.MaybeUninit<T>], A> throws AllocError {
    var a = allocator
    let (layout, offset, payload) = try slice_allocation_layout<T>(len)
    let raw = try a.allocate(layout)
    let h = raw.cast<LocalSharedHeader>()
    let data = unsafe { raw.add(offset) }.cast<core.mem.MaybeUninit<T>>()
    unsafe {
        core.ptr.write(h, LocalSharedHeader(1usize, 1usize, layout))
        if zeroed && payload.size() != 0usize {
            // Only the payload extent is zeroed; the reference-count header
            // remains initialized, and all payload slots remain MaybeUninit.
            core.ptr.write_bytes(data.cast<u8>(), 0u8, payload.size())
        }
    }
    LocalShared(slice_ptr_mut(data, len), h, a)
}

pub fn try_new_uninit_slice_in<T, A: Allocator>(
    len: usize,
    take allocator: A
): LocalShared<[core.mem.MaybeUninit<T>], A> throws AllocError {
    try try_new_slice_in<T, A>(len, allocator, false)
}

pub fn new_uninit_slice_in<T, A: Allocator>(
    len: usize,
    take allocator: A
): LocalShared<[core.mem.MaybeUninit<T>], A> {
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
): LocalShared<[core.mem.MaybeUninit<T>]> throws AllocError {
    try try_new_uninit_slice_in<T, Global>(len, Global())
}

pub fn new_uninit_slice<T>(len: usize): LocalShared<[core.mem.MaybeUninit<T>]> {
    new_uninit_slice_in<T, Global>(len, Global())
}

pub fn try_new_zeroed_slice_in<T, A: Allocator>(
    len: usize,
    take allocator: A
): LocalShared<[core.mem.MaybeUninit<T>], A> throws AllocError {
    try try_new_slice_in<T, A>(len, allocator, true)
}

pub fn new_zeroed_slice_in<T, A: Allocator>(
    len: usize,
    take allocator: A
): LocalShared<[core.mem.MaybeUninit<T>], A> {
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
): LocalShared<[core.mem.MaybeUninit<T>]> throws AllocError {
    try try_new_zeroed_slice_in<T, Global>(len, Global())
}

pub fn new_zeroed_slice<T>(len: usize): LocalShared<[core.mem.MaybeUninit<T>]> {
    new_zeroed_slice_in<T, Global>(len, Global())
}

// Copies only from a validated Text view, preserving Text's UTF-8 invariant.
pub fn try_copy_text_in<A: Allocator>(read value: Text, take allocator: A): LocalShared<Text, A> throws AllocError {
    var a = allocator
    let bytes = value.as_bytes()
    let result = capture extend_layout(layout_of<LocalSharedHeader>(), super.alloc.layout_of_val(bytes))
    let (layout, offset) = match take result {
        success((layout, offset)) => (layout.pad_to_align(), offset),
        failure(error) => throw AllocError(error.size, error.align)
    }
    let raw = try a.allocate(layout)
    let h = raw.cast<LocalSharedHeader>()
    let data = unsafe { raw.add(offset) }.cast<u8>()
    unsafe {
        core.ptr.write(h, LocalSharedHeader(1usize, 1usize, layout))
        core.ptr.copy(core.slice.data(bytes), data, bytes.len())
    }
    let slice = slice_ptr_mut(data, bytes.len())
    let text = unsafe { core.mem.transmute<ptr<mut Text>>(slice) }
    LocalShared(text, h, a)
}

pub fn copy_text_in<A: Allocator>(read value: Text, take allocator: A): LocalShared<Text, A> {
    let outcome = capture try_copy_text_in(value, allocator)
    match take outcome {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}

pub fn try_copy_text(read value: Text): LocalShared<Text> throws AllocError {
    try try_copy_text_in(value, Global())
}
pub fn copy_text(read value: Text): LocalShared<Text> { copy_text_in(value, Global()) }

fn bump(count: usize): usize {
    // Overflow would let a count wrap to zero and free a live payload.
    if count == 0xffffffffffffffffusize { core.intrinsics.abort() }
    count + 1usize
}

pub fn try_new_cyclic_in<T, A: Allocator + Clone, F: take fn(read Weak<T, A>): T>(
    take allocator: A,
    take make: F
): LocalShared<T, A> throws AllocError {
    var a = allocator
    let weak_allocator = a.clone()
    let (layout, offset) = try allocation_layout<T>()
    let raw = try a.allocate(layout)
    let h = raw.cast<LocalSharedHeader>()
    let p = unsafe { raw.add(offset) }.cast<T>()
    // Keep upgrades disabled until the payload is initialized; the guard
    // releases the implicit weak count if the constructor unwinds.
    unsafe { core.ptr.write(h, LocalSharedHeader(0usize, 2usize, layout)) }
    let weak_handle = Weak(p, h, weak_allocator)
    let _guard = WeakRelease(h, core.ptr.from_mut(a))
    let value = make(read weak_handle)
    unsafe {
        core.ptr.write(p, value)
        (*h).strong = 1usize
    }
    core.mem.forget(take _guard)
    LocalShared(p, h, a)
}
pub fn new_cyclic_in<T, A: Allocator + Clone, F: take fn(read Weak<T, A>): T>(
    take allocator: A,
    take make: F
): LocalShared<T, A> {
    let result = capture try_new_cyclic_in<T, A, F>(allocator, make)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
    }
}
pub fn try_new_cyclic<T, F: take fn(read Weak<T>): T>(take make: F): LocalShared<T> throws AllocError {
    try try_new_cyclic_in<T, Global, F>(Global(), make)
}
pub fn new_cyclic<T, F: take fn(read Weak<T>): T>(take make: F): LocalShared<T> {
    new_cyclic_in<T, Global, F>(Global(), make)
}

extend<T: unsized, A: Allocator + Clone> LocalShared<T, A> {
    // Another strong owner of the same payload; the payload is not cloned.
    pub fn retain(): LocalShared<T, A> {
        let allocator = self.a.clone()
        unsafe { (*self.h).strong = bump((*self.h).strong) }
        LocalShared(self.p, self.h, allocator)
    }
    pub fn downgrade(): Weak<T, A> {
        let allocator = self.a.clone()
        unsafe { (*self.h).wk = bump((*self.h).wk) }
        Weak(self.p, self.h, allocator)
    }
}
extend<T: unsized, A: Allocator + Clone> LocalShared<T, A> implements Clone {
    fn clone(): LocalShared<T, A> { self.retain() }
}

extend<T, A: Allocator> LocalShared<core.mem.MaybeUninit<T>, A> {
    // Safety: the caller initialized the payload before taking ownership as T.
    pub take unsafe fn assume_init(): LocalShared<T, A> {
        let raw = self.into_raw()
        unsafe { from_raw(RawLocalShared(raw.p.cast<T>(), raw.h, raw.a)) }
    }
}

extend<T, A: Allocator> LocalShared<[core.mem.MaybeUninit<T>], A> {
    // Safety: every element is initialized as T; element layout and length
    // metadata are unchanged by replacing MaybeUninit<T> with T.
    pub take unsafe fn assume_init(): LocalShared<[T], A> {
        let raw = self.into_raw()
        let slice = unsafe { core.mem.transmute<ptr<mut [T]>>(raw.p) }
        unsafe { from_raw(RawLocalShared(slice, raw.h, raw.a)) }
    }
}

extend<T: unsized, A: Allocator> LocalShared<T, A> {
    pub fn get(): read T from self { unsafe { read *self.p } }
    // The pointer is valid while this strong owner remains alive.
    pub fn as_ptr(): ptr<read T> { self.p.cast_const() }
    pub fn strong_count(): usize { unsafe { (*self.h).strong } }
    pub fn weak_count(): usize { unsafe { (*self.h).wk - 1usize } }
    pub fn ptr_eq(read other: LocalShared<T, A>): bool { self.h == other.h }
    pub fn is_unique(): bool { unsafe { (*self.h).strong == 1usize && (*self.h).wk == 1usize } }
    // Exclusive access only while no other strong or weak handle exists.
    pub mut fn get_mut(): (mut T from self)? {
        if self.is_unique() { present(unsafe { mut *self.p }) } else { none }
    }
}

extend<T, A: Allocator> LocalShared<T, A> {
    // Moves the payload out when this is the only strong owner; otherwise the
    // handle is returned unchanged. Weak handles may remain but can no longer
    // upgrade.
    pub take fn try_unwrap(): T throws LocalShared<T, A> {
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

extend<T: unsized, A: Allocator> LocalShared<T, A> {
    pub take fn into_raw(): RawLocalShared<T, A> {
        unsafe {
            let p = self.p
            let h = self.h
            let a = core.ptr.`read`(core.ptr.from_ref(self.a))
            core.mem.forget(take self)
            RawLocalShared(p, h, a)
        }
    }
}
pub unsafe fn from_raw<T: unsized, A: Allocator>(take raw: RawLocalShared<T, A>): LocalShared<T, A> {
    LocalShared(raw.p, raw.h, raw.a)
}
// Creates a second raw ownership token; consume both tokens exactly once.
pub unsafe fn increment_strong_count<T: unsized, A: Allocator + Clone>(
    read raw: RawLocalShared<T, A>
): RawLocalShared<T, A> {
    let allocator = raw.a.clone()
    unsafe { (*raw.h).strong = bump((*raw.h).strong) }
    RawLocalShared(raw.p, raw.h, allocator)
}
pub unsafe fn decrement_strong_count<T: unsized, A: Allocator>(take raw: RawLocalShared<T, A>): Unit {
    let _owner = unsafe { from_raw(raw) }
}

extend<T: unsized, A: Allocator + Clone> Weak<T, A> {
    pub fn upgrade(): LocalShared<T, A>? {
        if self.h == core.ptr.null_mut<LocalSharedHeader>() { return none }
        if unsafe { (*self.h).strong } == 0usize { return none }
        let allocator = self.a.clone()
        unsafe {
            let b = self.h
            if (*b).strong == 0usize { return none }
            (*b).strong = bump((*b).strong)
            present(LocalShared(self.p, b, allocator))
        }
    }
    pub fn retain(): Weak<T, A> {
        let allocator = self.a.clone()
        if self.h != core.ptr.null_mut<LocalSharedHeader>() {
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
pub unsafe fn weak_from_raw<T: unsized, A: Allocator>(take raw: RawWeak<T, A>): Weak<T, A> {
    // The raw token, including an empty null-header token, is reconstructed once.
    Weak(raw.p, raw.h, raw.a)
}
extend<T: unsized, A: Allocator> Weak<T, A> {
    // This pointer may dangle after the payload is dropped; upgrade before
    // dereferencing it.
    pub fn as_ptr(): ptr<read T> { self.p.cast_const() }
    pub fn strong_count(): usize {
        if self.h == core.ptr.null_mut<LocalSharedHeader>() { return 0usize }
        unsafe { (*self.h).strong }
    }
    pub fn weak_count(): usize {
        if self.h == core.ptr.null_mut<LocalSharedHeader>() { return 0usize }
        unsafe {
            if (*self.h).strong == 0usize {
                0usize
            } else {
                (*self.h).wk - 1usize
            }
        }
    }
    pub fn ptr_eq(read other: Weak<T, A>): bool { self.h == other.h }
}

extend<T: Clone, A: Allocator + Clone> LocalShared<T, A> {
    pub mut fn make_mut(): mut T from self {
        if self.is_unique() { return unsafe { mut *self.p } }
        let replacement = new_uninit_in<T, A>(self.a.clone())
        if unsafe { (*self.h).strong } == 1usize {
            unsafe {
                (*self.h).strong = 0usize
                core.ptr.write(replacement.p.cast<T>(), core.ptr.`read`(self.p))
            }
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

extend<T: Default> LocalShared<T> implements Default {
    static fn default(): LocalShared<T> { new(T.(Default).default()) }
}
extend<T> LocalShared<[T]> implements Default {
    static fn default(): LocalShared<[T]> {
        unsafe { new_zeroed_slice<T>(0usize).assume_init() }
    }
}
extend LocalShared<Text> implements Default {
    static fn default(): LocalShared<Text> { copy_text("") }
}

extend<T, A: Allocator> LocalShared<[T], A> implements From<super.vec.List<T, A>> {
    static fn from(take values: super.vec.List<T, A>): LocalShared<[T], A> {
        let source = values.into_heap_slice()
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
        let header = allocation.cast<LocalSharedHeader>()
        let destination = unsafe { allocation.add(offset) }.cast<core.mem.MaybeUninit<T>>()
        unsafe { core.ptr.write(header, LocalSharedHeader(1usize, 1usize, allocation_layout)) }

        var index = 0usize
        while index < length {
            // The consumed Heap owns exactly `length` initialized source items;
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
        var owner = LocalShared(slice, header, allocator)
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
extend<T, const N: usize> LocalShared<[T]> implements From<[T; N]> {
    static fn from(take items: [T; N]): LocalShared<[T]> {
        var owner = new_uninit_slice<T>(N)
        {
            let destination = match take owner.get_mut() {
                present(view) => view,
                none => core.intrinsics.abort()
            }
            let pointer = destination.as_mut_ptr()
            var index = 0usize
            for item in take items {
                // The iterator yields exactly N items, so each index is in bounds.
                unsafe {
                    core.ptr.write(
                        pointer.add(index),
                        core.mem.MaybeUninit<T>.new(item)
                    )
                }
                index += 1usize
            }
        }
        // The array iteration initializes every slot before ownership changes.
        unsafe { owner.assume_init() }
    }
}

extend<T, const N: usize, A: Allocator> LocalShared<[T; N], A>
    implements TryFrom<LocalShared<[T], A>>
{
    type Error = LocalShared<[T], A>

    static fn try_from(take value: LocalShared<[T], A>): Outcome<LocalShared<[T; N], A>, LocalShared<[T], A>> {
        if value.get().len() != N { return failure(value) }
        let raw = value.into_raw()
        // Equal lengths preserve layout when slice metadata becomes an array type.
        success(unsafe { from_raw(RawLocalShared(raw.p.cast<[T; N]>(), raw.h, raw.a)) })
    }
}

extend<T: unsized, A: Allocator> LocalShared<T, A> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get() }
}
extend<T: unsized, A: Allocator> LocalShared<T, A> implements AsRef<T> {
    fn as_ref(): read T from self { self.get() }
}
extend<T: unsized, A: Allocator> LocalShared<T, A> implements Borrow<T> {
    fn borrow(): read T from self { self.get() }
}
extend<T> LocalShared<T> implements From<T> {
    static fn from(take value: T): LocalShared<T> { new(value) }
}
extend<T: PartialEq + unsized, A: Allocator> LocalShared<T, A> implements PartialEq {
    fn eq(read other: LocalShared<T, A>): bool { self.get().eq(other.get()) }
}
extend<T: Eq + unsized, A: Allocator> LocalShared<T, A> implements Eq {}
extend<T: PartialOrd + unsized, A: Allocator> LocalShared<T, A> implements PartialOrd {
    fn partial_cmp(read other: LocalShared<T, A>): Ordering? { self.get().partial_cmp(other.get()) }
}
extend<T: Ord + unsized, A: Allocator> LocalShared<T, A> implements Ord {
    fn cmp(read other: LocalShared<T, A>): Ordering { self.get().cmp(other.get()) }
}
extend<T: Hash + unsized, A: Allocator> LocalShared<T, A> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.get().hash(mut state) }
}
extend<T: fmt.Display + unsized, A: Allocator> LocalShared<T, A> implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try T.(fmt.Display).fmt(self.get(), mut f) }
}
extend<T: fmt.Debug + unsized, A: Allocator> LocalShared<T, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try T.(fmt.Debug).fmt(self.get(), mut f) }
}

extend<A: Allocator> LocalShared<any Any, A> {
    pub take fn downcast<T: Static>(): Outcome<LocalShared<T, A>, LocalShared<any Any, A>> {
        if !core.any.is<T>(self.get()) { return failure(self) }
        let raw = self.into_raw()
        // A matching TypeId guarantees the erased payload has T's layout.
        success(unsafe { from_raw(RawLocalShared(raw.p.cast<T>(), raw.h, raw.a)) })
    }
}

// Shared owner whose payload never moves until the last owner destroys it.
// Only `pin` creates one: an existing `LocalShared` may have unpinned siblings that
// could still move the payload out. Owners reach the payload only by
// shared or pinned-read access.
pub type Pinned<T: unsized, A: Allocator = Global> {
    p: ptr<mut T>
    h: ptr<mut LocalSharedHeader>
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
extend<T: Eq + unsized, A: Allocator> Pinned<T, A> implements Eq {}
extend<T: Ord + unsized, A: Allocator> Pinned<T, A> implements Ord {
    fn cmp(read other: Pinned<T, A>): Ordering { self.get_ref().cmp(other.get_ref()) }
}
extend<T: Hash + unsized, A: Allocator> Pinned<T, A> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.get_ref().hash(mut state) }
}
extend<T: fmt.Display + unsized, A: Allocator> Pinned<T, A> implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try T.(fmt.Display).fmt(self.get_ref(), mut f) }
}
extend<T: fmt.Debug + unsized, A: Allocator> Pinned<T, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try T.(fmt.Debug).fmt(self.get_ref(), mut f) }
}
extend<T: PartialEq<U> + unsized, U: unsized, A: Allocator, B: Allocator> Pinned<T, A> implements PartialEq<Pinned<U, B>> {
    fn eq(read other: Pinned<U, B>): bool { self.get_ref().eq(other.get_ref()) }
}
extend<T: PartialOrd<U> + unsized, U: unsized, A: Allocator, B: Allocator> Pinned<T, A> implements PartialOrd<Pinned<U, B>> {
    fn partial_cmp(read other: Pinned<U, B>): Ordering? { self.get_ref().partial_cmp(other.get_ref()) }
}
extend<T: PartialEq<U> + unsized, U: unsized, A: Allocator, B: Allocator> Pinned<T, A> implements PartialEq<super.boxed.Pinned<U, B>> {
    fn eq(read other: super.boxed.Pinned<U, B>): bool { self.get_ref().eq(other.get_ref()) }
}
extend<T: PartialOrd<U> + unsized, U: unsized, A: Allocator, B: Allocator> Pinned<T, A> implements PartialOrd<super.boxed.Pinned<U, B>> {
    fn partial_cmp(read other: super.boxed.Pinned<U, B>): Ordering? { self.get_ref().partial_cmp(other.get_ref()) }
}
extend<T: PartialEq<U> + unsized, U: unsized, A: Allocator, B: Allocator> Pinned<T, A> implements PartialEq<super.arc.Pinned<U, B>> {
    fn eq(read other: super.arc.Pinned<U, B>): bool { self.get_ref().eq(other.get_ref()) }
}
extend<T: PartialOrd<U> + unsized, U: unsized, A: Allocator, B: Allocator> Pinned<T, A> implements PartialOrd<super.arc.Pinned<U, B>> {
    fn partial_cmp(read other: super.arc.Pinned<U, B>): Ordering? { self.get_ref().partial_cmp(other.get_ref()) }
}
extend<region r, T: PartialEq<U> + unsized, U: unsized, A: Allocator> Pinned<T, A> implements PartialEq<pinned read U from r> {
    fn eq(read other: pinned read U from r): bool { self.get_ref().eq(other.get_ref()) }
}
extend<region r, T: PartialOrd<U> + unsized, U: unsized, A: Allocator> Pinned<T, A> implements PartialOrd<pinned read U from r> {
    fn partial_cmp(read other: pinned read U from r): Ordering? { self.get_ref().partial_cmp(other.get_ref()) }
}
extend<region r, T: PartialEq<U> + unsized, U: unsized, A: Allocator> Pinned<T, A> implements PartialEq<pinned mut U from r> {
    fn eq(read other: pinned mut U from r): bool { self.get_ref().eq(other.get_ref()) }
}
extend<region r, T: PartialOrd<U> + unsized, U: unsized, A: Allocator> Pinned<T, A> implements PartialOrd<pinned mut U from r> {
    fn partial_cmp(read other: pinned mut U from r): Ordering? { self.get_ref().partial_cmp(other.get_ref()) }
}
extend<region r, T: PartialEq<U> + unsized, U: unsized, A: Allocator> pinned read T from r implements PartialEq<Pinned<U, A>> {
    fn eq(read other: Pinned<U, A>): bool { self.get_ref().eq(other.get_ref()) }
}
extend<region r, T: PartialOrd<U> + unsized, U: unsized, A: Allocator> pinned read T from r implements PartialOrd<Pinned<U, A>> {
    fn partial_cmp(read other: Pinned<U, A>): Ordering? { self.get_ref().partial_cmp(other.get_ref()) }
}
extend<region r, T: PartialEq<U> + unsized, U: unsized, A: Allocator> pinned mut T from r implements PartialEq<Pinned<U, A>> {
    fn eq(read other: Pinned<U, A>): bool { self.get_ref().eq(other.get_ref()) }
}
extend<region r, T: PartialOrd<U> + unsized, U: unsized, A: Allocator> pinned mut T from r implements PartialOrd<Pinned<U, A>> {
    fn partial_cmp(read other: Pinned<U, A>): Ordering? { self.get_ref().partial_cmp(other.get_ref()) }
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
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str("(Weak)") }
}
extend<region r> LocalShared<Text> implements From<read Text from r> {
    static fn from(take value: read Text from r): LocalShared<Text> { copy_text(value) }
}
extend LocalShared<Text> implements From<super.string.String> {
    static fn from(take value: super.string.String): LocalShared<Text> { copy_text(value.as_text()) }
}
extend<region r> LocalShared<Text> implements From<mut Text from r> {
    static fn from(take value: mut Text from r): LocalShared<Text> { copy_text(read value) }
}
extend<T: unsized, A: Allocator> LocalShared<T, A> implements From<super.boxed.Heap<T, A>> {
    static fn from(take value: super.boxed.Heap<T, A>): LocalShared<T, A> {
        let moved = capture unsafe { value.try_move_with_prefix(layout_of<LocalSharedHeader>()) }
        let (pointer, block, allocation, source, source_layout, allocator) = match take moved {
            success(parts) => parts,
            failure(error) => handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
        }
        let header = block.cast<LocalSharedHeader>()
        unsafe { core.ptr.write(header, LocalSharedHeader(1usize, 1usize, allocation)) }
        var owner = LocalShared(pointer, header, allocator)
        let _release_source = unsafe {
            super.alloc.free_block(source, source_layout, core.ptr.from_mut(owner.a))
        }
        core.mem.drop(take _release_source)
        owner
    }
}
extend LocalShared<core.ffi.CStr> implements From<super.ffi.CString> {
    static fn from(take value: super.ffi.CString): LocalShared<core.ffi.CStr> {
        LocalShared<core.ffi.CStr>.(From<super.boxed.Heap<core.ffi.CStr>>).from(
            value.into_heap_c_str()
        )
    }
}
extend<region r> LocalShared<core.ffi.CStr> implements From<read core.ffi.CStr from r> {
    static fn from(take value: read core.ffi.CStr from r): LocalShared<core.ffi.CStr> {
        LocalShared<core.ffi.CStr>.(From<super.ffi.CString>).from(value.to_owned())
    }
}
extend<region r> LocalShared<core.ffi.CStr> implements From<mut core.ffi.CStr from r> {
    static fn from(take value: mut core.ffi.CStr from r): LocalShared<core.ffi.CStr> {
        LocalShared<core.ffi.CStr>.(From<super.ffi.CString>).from(value.to_owned())
    }
}
extend<region r, B: core.borrow.ToOwned + unsized> LocalShared<B> implements From<super.borrow.BorrowedOrOwned<region r, B>> where LocalShared<B>: From<read B from r> + From<B.Owned> {
    static fn from(take value: super.borrow.BorrowedOrOwned<region r, B>): LocalShared<B> {
        match take value {
            super.borrow.BorrowedOrOwned.Borrowed(view) => LocalShared<B>.(From<read B from r>).from(view),
            super.borrow.BorrowedOrOwned.Owned(owner) => LocalShared<B>.(From<B.Owned>).from(owner)
        }
    }
}
extend<A: Allocator> LocalShared<[u8], A> implements From<LocalShared<Text, A>> {
    static fn from(take value: LocalShared<Text, A>): LocalShared<[u8], A> {
        let raw = value.into_raw()
        // Text is a byte-slice tail with identical metadata and alignment.
        let bytes = unsafe { core.mem.transmute<ptr<mut [u8]>>(raw.p) }
        LocalShared(bytes, raw.h, raw.a)
    }
}
extend<region r, T: Clone> LocalShared<[T]> implements From<read [T] from r> {
    static fn from(take values: read [T] from r): LocalShared<[T]> {
        var copies = super.vec.with_capacity<T>(values.len())
        var index = 0usize
        while index < values.len() {
            copies.push(values[index].clone())
            index += 1usize
        }
        LocalShared<[T]>.from(copies)
    }
}
extend<region r, T: Clone> LocalShared<[T]> implements From<mut [T] from r> {
    static fn from(take values: mut [T] from r): LocalShared<[T]> {
        LocalShared<[T]>.from(values.to_vec())
    }
}
extend<T> LocalShared<[T]> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(take items: I): LocalShared<[T]> {
        let values = super.vec.List<T>.(FromItems<T>).from_iter(items)
        LocalShared<[T]>.from(values)
    }
}
