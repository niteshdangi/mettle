import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.fmt
import package.core.hash.{Hash, Hasher}
import package.core.ops.Deref
import super.alloc.{Allocator, Global, AllocError, Layout, layout_of, extend_layout, handle_alloc_error, layout_unchecked}
import package.core.clone.Clone
import package.core.text.Text
import super.vec.slice_ptr_mut

type RcHeader {
    strong: usize
    wk: usize
    allocation: Layout
}

// Raw handles are ownership tokens carrying both the payload and count header.
// Reconstruct each token exactly once with the matching from_raw function.
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
        unsafe {
            let _guard = WeakRelease(self.h, core.ptr.from_mut(self.a))
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

pub fn try_new_uninit_in<T, A: Allocator>(
    allocator: take A
): Rc<core.mem.MaybeUninit<T>, A> throws AllocError {
    try_new_in(core.mem.MaybeUninit<T>.uninit(), allocator)
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
    try_new_in(core.mem.MaybeUninit<T>.zeroed(), allocator)
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
        unsafe { core.mem.transmute<Rc<T, A>>(take self) }
    }
}

extend<T: unsized, A: Allocator> Rc<T, A> {
    pub fn get(): read T from self { unsafe { read *self.p } }
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
        unsafe {
            let b = self.h
            if (*b).strong == 0usize { return none }
            (*b).strong = bump((*b).strong)
            present(Rc(self.p, b, self.a.clone()))
        }
    }
    pub fn retain(): Weak<T, A> {
        let allocator = self.a.clone()
        unsafe { (*self.h).wk = bump((*self.h).wk) }
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
pub unsafe fn weak_from_raw<T: unsized, A: Allocator>(raw: take RawWeak<T, A>): Weak<T, A> {
    Weak(raw.p, raw.h, raw.a)
}
extend<T: unsized, A: Allocator> Weak<T, A> {
    pub fn strong_count(): usize { unsafe { (*self.h).strong } }
    pub fn weak_count(): usize {
        unsafe {
            if (*self.h).strong == 0usize {
                (*self.h).wk
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


// Shared handles compare, hash and format as their payload; `ptr_eq` tests identity.
extend<T: unsized, A: Allocator> Rc<T, A> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get() }
}
extend<T: PartialEq, A: Allocator> Rc<T, A> implements PartialEq {
    fn eq(other: read Rc<T, A>): bool { self.get().eq(other.get()) }
}
extend<T: Eq, A: Allocator> Rc<T, A> implements Eq {}
extend<T: PartialOrd, A: Allocator> Rc<T, A> implements PartialOrd {
    fn partial_cmp(other: read Rc<T, A>): Ordering? { self.get().partial_cmp(other.get()) }
}
extend<T: Ord, A: Allocator> Rc<T, A> implements Ord {
    fn cmp(other: read Rc<T, A>): Ordering { self.get().cmp(other.get()) }
}
extend<T: Hash, A: Allocator> Rc<T, A> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.get().hash(mut state) }
}
extend<T: fmt.Display, A: Allocator> Rc<T, A> implements fmt.Display {
    fn fmt<W: fmt.Write>(f: mut fmt.Formatter<W>): Unit throws fmt.Error { try T.(fmt.Display).fmt(self.get(), mut f) }
}
extend<T: fmt.Debug, A: Allocator> Rc<T, A> implements fmt.Debug {
    fn fmt<W: fmt.Write>(f: mut fmt.Formatter<W>): Unit throws fmt.Error { try T.(fmt.Debug).fmt(self.get(), mut f) }
}
