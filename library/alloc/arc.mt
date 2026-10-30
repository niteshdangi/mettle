// Atomically reference-counted shared owner. Counting is atomic; that makes
// the handles themselves thread-safe, not the payload: an `Arc<T>` crosses or
// is shared between threads only when `T` is both Transferable and Shareable.
import super.alloc.{Allocator, Global, AllocError, Layout, layout_of, handle_alloc_error};
import package.core.clone.Clone;

// Shared header and payload. `wk` counts every Weak plus one implicit
// reference held collectively by all strong owners, so the block is released
// exactly when the last of them is gone.
type ArcBox<T> {
    strong: core.sync.atomic.AtomicUsize
    wk: core.sync.atomic.AtomicUsize
    value: core.mem.MaybeUninit<T>
}

pub type Arc<T, A: Allocator = Global> {
    p: ptr<mut ArcBox<T>>
    a: A
    drop {
        unsafe {
            let b = self.p
            // Release publishes this owner's uses of the payload; the owner
            // that observes the last count acquires all of them before drop.
            if (*b).strong.fetch_sub(1usize, core.sync.atomic.Ordering.Release) == 1usize {
                core.sync.atomic.fence(core.sync.atomic.Ordering.Acquire)
                let _implicit = WeakRelease(b, core.ptr.from_mut(self.a))
                core.ptr.drop_in_place((*b).value.as_mut_ptr())
            }
        }
    }
}

// Non-owning handle: keeps the block (not the payload) alive.
pub type Weak<T, A: Allocator = Global> {
    p: ptr<mut ArcBox<T>>
    a: A
    drop {
        unsafe {
            let _guard = WeakRelease(self.p, core.ptr.from_mut(self.a))
        }
    }
}

// Drops one weak reference and frees the block when none remain.
type WeakRelease<T, A: Allocator> {
    p: ptr<mut ArcBox<T>>
    a: ptr<mut A>
    drop {
        unsafe {
            let b = self.p
            if (*b).wk.fetch_sub(1usize, core.sync.atomic.Ordering.Release) == 1usize {
                core.sync.atomic.fence(core.sync.atomic.Ordering.Acquire)
                (*self.a).deallocate(b.cast<u8>(), layout_of<ArcBox<T>>())
            }
        }
    }
}

// Transfer and sharing of the handles require the payload to be both
// Transferable and Shareable (the last owner may drop it on any thread, and
// every owner may read it concurrently) and the allocator to cross threads.
unsafe extend<T: Transferable + Shareable, A: Allocator + Transferable> Arc<T, A> implements Transferable {}
unsafe extend<T: Transferable + Shareable, A: Allocator + Shareable> Arc<T, A> implements Shareable {}
unsafe extend<T: Transferable + Shareable, A: Allocator + Transferable> Weak<T, A> implements Transferable {}
unsafe extend<T: Transferable + Shareable, A: Allocator + Shareable> Weak<T, A> implements Shareable {}

pub fn try_new_in<T, A: Allocator>(value: take T, allocator: take A): Arc<T, A> throws AllocError {
    var a = allocator
    let raw = try a.allocate(layout_of<ArcBox<T>>())
    let b = raw.cast<ArcBox<T>>()
    unsafe {
        core.ptr.write(b, ArcBox(core.sync.atomic.AtomicUsize.new(1usize),
                                   core.sync.atomic.AtomicUsize.new(1usize),
                                   core.mem.MaybeUninit.new(value)))
    }
    Arc(b, a)
}
pub fn new_in<T, A: Allocator>(value: take T, allocator: take A): Arc<T, A> {
    let outcome = capture try_new_in(value, allocator)
    match take outcome {
        success(r) => r,
        failure(e) => handle_alloc_error(layout_of<ArcBox<T>>())
    }
}
pub fn new<T>(value: take T): Arc<T> { new_in(value, Global()) }
pub fn try_new<T>(value: take T): Arc<T> throws AllocError { try try_new_in(value, Global()) }

// Increments a live count; overflow would let it wrap to zero and free a live
// payload, so it aborts.
unsafe fn increment(count: ptr<mut core.sync.atomic.AtomicUsize>) {
    let previous = (*count).fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
    if previous > 0x7fffffffffffffffusize { core.intrinsics.abort() }
}

extend<T, A: Allocator + Clone> Arc<T, A> {
    // Another strong owner of the same payload; the payload is not cloned.
    pub fn retain(): Arc<T, A> {
        unsafe { increment(core.ptr.from_mut((*self.p).strong)) }
        Arc(self.p, self.a.clone())
    }
    pub fn downgrade(): Weak<T, A> {
        unsafe { increment(core.ptr.from_mut((*self.p).wk)) }
        Weak(self.p, self.a.clone())
    }
}
extend<T, A: Allocator + Clone> Arc<T, A> implements Clone {
    fn clone(): Arc<T, A> { self.retain() }
}

extend<T, A: Allocator> Arc<T, A> {
    pub fn get(): read T from self { unsafe { read *(*self.p).value.as_ptr() } }
    pub fn strong_count(): usize { unsafe { (*self.p).strong.load(core.sync.atomic.Ordering.Acquire) } }
    pub fn weak_count(): usize { unsafe { (*self.p).wk.load(core.sync.atomic.Ordering.Acquire) - 1usize } }
    pub fn ptr_eq(other: read Arc<T, A>): bool { self.p == other.p }
    // Exclusive access only while no other strong or weak handle exists. A
    // weak handle can only be created through a strong one, so when this
    // handle is the sole owner nothing can race with the check.
    pub mut fn get_mut(): (mut T from self)? {
        unsafe {
            let b = self.p
            let unique = (*b).wk.load(core.sync.atomic.Ordering.Acquire) == 1usize &&
                         (*b).strong.load(core.sync.atomic.Ordering.Acquire) == 1usize
            if unique { present(mut *(*b).value.as_mut_ptr()) } else { none }
        }
    }
    // Moves the payload out when this is the only strong owner; otherwise the
    // handle is returned unchanged. Weak handles may remain but can no longer
    // upgrade.
    pub take fn try_unwrap(): T throws Arc<T, A> {
        unsafe {
            let b = self.p
            if (*b).strong.compare_exchange(1usize, 0usize, core.sync.atomic.Ordering.Acquire,
                                            core.sync.atomic.Ordering.Relaxed).is_failure() { throw self }
            let value = core.ptr.`read`((*b).value.as_ptr())
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
}

extend<T, A: Allocator + Clone> Weak<T, A> {
    // Succeeds only while a strong owner exists; the count only moves up from
    // a nonzero value, so a block already being destroyed is never revived.
    pub fn upgrade(): Arc<T, A>? {
        unsafe {
            let b = self.p
            var current = (*b).strong.load(core.sync.atomic.Ordering.Relaxed)
            while current != 0usize {
                if current > 0x7fffffffffffffffusize { core.intrinsics.abort() }
                match (*b).strong.compare_exchange_weak(current, current + 1usize,
                        core.sync.atomic.Ordering.Acquire, core.sync.atomic.Ordering.Relaxed) {
                    success(_) => { return present(Arc(b, self.a.clone())) },
                    failure(seen) => { current = seen }
                }
            }
            none
        }
    }
    pub fn retain(): Weak<T, A> {
        unsafe { increment(core.ptr.from_mut((*self.p).wk)) }
        Weak(self.p, self.a.clone())
    }
}
extend<T, A: Allocator> Weak<T, A> {
    pub fn strong_count(): usize { unsafe { (*self.p).strong.load(core.sync.atomic.Ordering.Acquire) } }
}
