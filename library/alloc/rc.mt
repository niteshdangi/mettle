import package::core::cmp::{Eq, Ord, Ordering, PartialEq, PartialOrd};
import package::core::fmt;
import package::core::hash::{Hash, Hasher};
import package::core::ops::Deref;
import super::alloc::{Allocator, Global, AllocError, Layout, layout_of, handle_alloc_error};
import package::core::clone::Clone;

// Shared header and payload. `wk` counts every Weak plus one implicit
// reference held collectively by all strong owners, so the block is released
// exactly when the last of them is gone.
type RcBox<T> {
    strong: usize
    wk: usize
    value: core::mem::MaybeUninit<T>
}

// Single-threaded shared owner; the allocator travels with each handle.
pub type Rc<T, A: Allocator = Global> {
    p: ptr<mut RcBox<T>>
    a: A
    drop {
        unsafe {
            let b = self.p
            (*b).strong -= 1usize
            if (*b).strong == 0usize {
                let _implicit = WeakRelease(b, core::ptr::from_mut(self.a))
                core::ptr::drop_in_place((*b).value.as_mut_ptr())
            }
        }
    }
}

// Non-owning handle: keeps the block (not the payload) alive.
pub type Weak<T, A: Allocator = Global> {
    p: ptr<mut RcBox<T>>
    a: A
    drop {
        unsafe {
            let _guard = WeakRelease(self.p, core::ptr::from_mut(self.a))
        }
    }
}

// Drops one weak reference and frees the block when none remain.
type WeakRelease<T, A: Allocator> {
    p: ptr<mut RcBox<T>>
    a: ptr<mut A>
    drop {
        unsafe {
            let b = self.p
            (*b).wk -= 1usize
            if (*b).wk == 0usize { (*self.a).deallocate(b.cast::<u8>(), layout_of::<RcBox<T>>()) }
        }
    }
}

pub fn try_new_in<T, A: Allocator>(value: take T, allocator: take A): Rc<T, A> throws AllocError {
    var a = allocator
    let raw = try a.allocate(layout_of::<RcBox<T>>())
    let b = raw.cast::<RcBox<T>>()
    unsafe { core::ptr::write(b, RcBox(1usize, 1usize, core::mem::MaybeUninit::new(value))) }
    Rc(b, a)
}
pub fn new_in<T, A: Allocator>(value: take T, allocator: take A): Rc<T, A> {
    let outcome = capture try_new_in(value, allocator)
    match take outcome {
        success(r) => r,
        failure(e) => handle_alloc_error(layout_of::<RcBox<T>>())
    }
}
pub fn new<T>(value: take T): Rc<T> { new_in(value, Global()) }
pub fn try_new<T>(value: take T): Rc<T> throws AllocError { try try_new_in(value, Global()) }

fn bump(count: usize): usize {
    // Overflow would let a count wrap to zero and free a live payload.
    if count == 0xffffffffffffffffusize { core::intrinsics::abort() }
    count + 1usize
}

impl<T, A: Allocator + Clone> Rc<T, A> {
    // Another strong owner of the same payload; the payload is not cloned.
    pub fn retain(): Rc<T, A> {
        unsafe { (*self.p).strong = bump((*self.p).strong) }
        Rc(self.p, self.a.clone())
    }
    pub fn downgrade(): Weak<T, A> {
        unsafe { (*self.p).wk = bump((*self.p).wk) }
        Weak(self.p, self.a.clone())
    }
}
impl<T, A: Allocator + Clone> Rc<T, A> implements Clone {
    fn clone(): Rc<T, A> { self.retain() }
}

impl<T, A: Allocator> Rc<T, A> {
    pub fn get(): read T from self { unsafe { read *(*self.p).value.as_ptr() } }
    pub fn strong_count(): usize { unsafe { (*self.p).strong } }
    pub fn weak_count(): usize { unsafe { (*self.p).wk - 1usize } }
    pub fn ptr_eq(other: read Rc<T, A>): bool { self.p == other.p }
    pub fn is_unique(): bool { unsafe { (*self.p).strong == 1usize && (*self.p).wk == 1usize } }
    // Exclusive access only while no other strong or weak handle exists.
    pub mut fn get_mut(): (mut T from self)? {
        if self.is_unique() { present(unsafe { mut *(*self.p).value.as_mut_ptr() }) } else { none }
    }
    // Moves the payload out when this is the only strong owner; otherwise the
    // handle is returned unchanged. Weak handles may remain but can no longer
    // upgrade.
    pub take fn try_unwrap(): T throws Rc<T, A> {
        if unsafe { (*self.p).strong } != 1usize { throw self }
        unsafe {
            let b = self.p
            let value = core::ptr::`read`((*b).value.as_ptr())
            (*b).strong = 0usize
            var a = core::ptr::`read`(core::ptr::from_ref(self.a))
            core::mem::forget(take self)
            let _implicit = WeakRelease(b, core::ptr::from_mut(a))
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
}

impl<T, A: Allocator + Clone> Weak<T, A> {
    pub fn upgrade(): Rc<T, A>? {
        unsafe {
            let b = self.p
            if (*b).strong == 0usize { return none }
            (*b).strong = bump((*b).strong)
            present(Rc(b, self.a.clone()))
        }
    }
    pub fn retain(): Weak<T, A> {
        unsafe { (*self.p).wk = bump((*self.p).wk) }
        Weak(self.p, self.a.clone())
    }
}
impl<T, A: Allocator> Weak<T, A> {
    pub fn strong_count(): usize { unsafe { (*self.p).strong } }
}


// Shared handles compare, hash and format as their payload; `ptr_eq` tests identity.
impl<T, A: Allocator> Rc<T, A> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get() }
}
impl<T: PartialEq, A: Allocator> Rc<T, A> implements PartialEq {
    fn eq(other: read Rc<T, A>): bool { self.get().eq(other.get()) }
}
impl<T: Eq, A: Allocator> Rc<T, A> implements Eq {}
impl<T: PartialOrd, A: Allocator> Rc<T, A> implements PartialOrd {
    fn partial_cmp(other: read Rc<T, A>): Ordering? { self.get().partial_cmp(other.get()) }
}
impl<T: Ord, A: Allocator> Rc<T, A> implements Ord {
    fn cmp(other: read Rc<T, A>): Ordering { self.get().cmp(other.get()) }
}
impl<T: Hash, A: Allocator> Rc<T, A> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.get().hash(mut state) }
}
impl<T: fmt::Display, A: Allocator> Rc<T, A> implements fmt::Display {
    fn fmt<W: fmt::Write>(f: mut fmt::Formatter<W>): Unit throws fmt::Error { try <T implements fmt::Display>::fmt(self.get(), mut f) }
}
impl<T: fmt::Debug, A: Allocator> Rc<T, A> implements fmt::Debug {
    fn fmt<W: fmt::Write>(f: mut fmt::Formatter<W>): Unit throws fmt::Error { try <T implements fmt::Debug>::fmt(self.get(), mut f) }
}
