import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.fmt
import package.core.hash.{Hash, Hasher}
import package.core.ops.{Deref, DerefMut}
import package.core.future.{Future, Context, Poll}
import super.alloc.{Allocator, Global, AllocError, Layout, layout_of, layout_of_val, free_block, handle_alloc_error}
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

extend<T: unsized, A: Allocator> Box<T, A> {
    pub fn get(): read T from self { unsafe { read *self.p } }
    pub mut fn get_mut(): mut T from self { unsafe { mut *self.p } }
    pub fn allocator(): read A from self { read self.a }
    pub fn as_ptr(): ptr<mut T> { self.p }
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

// Unique heap owner whose payload stays at its address until destruction.
// Moving the handle never moves the payload; safe code reaches the payload
// mutably only through a pinned view, or directly when it is Unpin.
pub type Pinned<T: unsized, A: Allocator = super.alloc.Global> {
    p: ptr<mut T>
    a: A
    drop {
        let _free = unsafe { free_block(self.p.cast<u8>(), layout_of_val(self.get_ref()), core.ptr.from_mut(self.a)) }
        unsafe { core.ptr.drop_in_place(self.p) }
    }
}

// `pinned heap value`: the payload is pinned from its first use.
pub fn pin<T>(value: take T): Pinned<T> { new(value).into_pinned() }

extend<T: unsized, A: Allocator> Box<T, A> {
    // A unique heap payload does not move when its owner moves, so pinning
    // consumes the owner and nothing safe can move the payload out again.
    pub take fn into_pinned(): Pinned<T, A> {
        let raw = self.into_raw()
        Pinned(raw.0, raw.1)
    }
}

extend<T: unsized, A: Allocator> Pinned<T, A> {
    pub fn as_ref(): pinned read T from self { unsafe { core.pin.Pin.new_unchecked(read *self.p) } }
    pub mut fn as_mut(): pinned mut T from self { unsafe { core.pin.Pin.new_unchecked(mut *self.p) } }
    pub fn get_ref(): read T from self { unsafe { read *self.p } }
    pub fn allocator(): read A from self { read self.a }
    // Safety: the payload stays at its address until it is destroyed, even
    // after the returned owner no longer pins it.
    pub take unsafe fn into_inner_unchecked(): Box<T, A> {
        unsafe {
            let p = self.p
            let a = core.ptr.`read`(core.ptr.from_ref(self.a))
            core.mem.forget(take self)
            from_raw_in(p, a)
        }
    }
}

extend<T: unsized + Unpin, A: Allocator> Pinned<T, A> {
    pub mut fn get_mut(): mut T from self { unsafe { mut *self.p } }
    pub take fn into_inner(): Box<T, A> { unsafe { self.into_inner_unchecked() } }
}

extend<T: unsized, A: Allocator> Pinned<T, A> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get_ref() }
}
extend<T: unsized + Unpin, A: Allocator> Pinned<T, A> implements DerefMut {
    type Target = T
    mut fn deref_mut(): mut T from self { self.get_mut() }
}
// Awaiting a pinned owner polls its payload in place.
extend<T: unsized + Future, A: Allocator> Pinned<T, A> implements Future {
    type Output = T.(Future).Output
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<T.(Future).Output> {
        let owner: mut Pinned<T, A> = unsafe { self.get_unchecked_mut() }
        owner.as_mut().poll(mut cx)
    }
}
extend<T: fmt.Debug, A: Allocator> Pinned<T, A> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try T.(fmt.Debug).fmt(self.get_ref(), mut f) }
}
// The handle is movable; pinning is a property of the payload's storage.
unsafe extend<T: unsized, A: Allocator> Pinned<T, A> implements Unpin {}
unsafe extend<T: Transferable, A: Allocator + Transferable> Pinned<T, A> implements Transferable {}
unsafe extend<T: Shareable, A: Allocator + Shareable> Pinned<T, A> implements Shareable {}
