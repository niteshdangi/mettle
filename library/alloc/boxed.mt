import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.fmt
import package.core.hash.{Hash, Hasher}
import package.core.ops.{Deref, DerefMut}
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
    fn fmt<W: fmt.Write>(f: mut fmt.Formatter<W>): Unit throws fmt.Error { try T.(fmt.Display).fmt(self.get(), mut f) }
}
extend<T: fmt.Debug, A: Allocator> Box<T, A> implements fmt.Debug {
    fn fmt<W: fmt.Write>(f: mut fmt.Formatter<W>): Unit throws fmt.Error { try T.(fmt.Debug).fmt(self.get(), mut f) }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<T: Transferable, A: Allocator + Transferable> Box<T, A> implements Transferable {}
unsafe extend<T: Shareable, A: Allocator + Shareable> Box<T, A> implements Shareable {}
