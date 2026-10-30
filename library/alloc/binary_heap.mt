import package::core::iter::{Iterator, IntoIterator, Iterable, FromIterator, Extend};
import package::core::clone::Clone;
import package::core::fmt;
import package::core::slice::SliceIter;
import super::alloc::{Allocator, Global, AllocError};
import super::vec::Vec;
import package::core::cmp::Ord;

// Max-heap on a `Vec`.
pub type BinaryHeap<T, A: Allocator = Global> { data: Vec<T, A> }

pub fn new_in<T, A: Allocator>(a: take A): BinaryHeap<T, A> { BinaryHeap(super::vec::new_in::<T, A>(a)) }
pub fn new<T>(): BinaryHeap<T> { new_in(Global()) }

impl<T: Ord, A: Allocator> BinaryHeap<T, A> {
    pub fn len(): usize { self.data.len() }
    pub fn is_empty(): bool { self.data.is_empty() }
    pub fn peek(): (read T from self)? { self.data.get(0usize) }
    pub fn as_slice(): read [T] from self { self.data.as_slice() }
    pub take fn into_vec(): Vec<T, A> {
        unsafe {
            let v = core::ptr::`read`(core::ptr::from_ref(self.data))
            core::mem::forget(take self)
            v
        }
    }

    mut fn sift_up(start: usize): Unit {
        var i = start
        while i > 0usize {
            let parent = (i - 1usize) / 2usize
            if self.data[i].cmp(self.data[parent]).is_gt() {
                self.data.swap(i, parent)
                i = parent
            } else {
                return ()
            }
        }
    }
    mut fn sift_down(start: usize): Unit {
        let n = self.data.len()
        var i = start
        while true {
            let l = 2usize * i + 1usize
            if l >= n { return () }
            var big = l
            if l + 1usize < n && self.data[l + 1usize].cmp(self.data[l]).is_gt() { big = l + 1usize }
            if self.data[big].cmp(self.data[i]).is_gt() {
                self.data.swap(big, i)
                i = big
            } else {
                return ()
            }
        }
    }
    pub mut fn try_push(value: take T): Unit throws AllocError {
        try self.data.try_push(value)
        let last = self.data.len() - 1usize
        self.sift_up(last)
    }
    pub mut fn push(value: take T): Unit {
        self.data.push(value)
        let last = self.data.len() - 1usize
        self.sift_up(last)
    }
    pub mut fn pop(): T? {
        let n = self.data.len()
        if n == 0usize { return none }
        self.data.swap(0usize, n - 1usize)
        let top = self.data.pop()
        self.sift_down(0usize)
        top
    }
    pub mut fn clear(): Unit { self.data.clear() }
}


// Iteration is in heap (storage) order, not sorted order.
impl<T, A: Allocator> BinaryHeap<T, A> implements Iterable {
    type Item = T
    type Iter<region r> = SliceIter<region r, T>
    fn iter<region r>(receiver self: read Self from r): SliceIter<region r, T> { self.data.as_slice().iter() }
}

impl<T: Clone, A: Allocator + Clone> BinaryHeap<T, A> implements Clone {
    fn clone(): BinaryHeap<T, A> { BinaryHeap(self.data.clone()) }
}
// Elements appear in heap (storage) order.
impl<T: fmt::Debug, A: Allocator> BinaryHeap<T, A> implements fmt::Debug {
    fn fmt<W: fmt::Write>(f: mut fmt::Formatter<W>): Unit throws fmt::Error {
        try <[T] implements fmt::Debug>::fmt(self.data.as_slice(), mut f)
    }
}
impl<T: Ord, A: Allocator> BinaryHeap<T, A> implements Extend<T> {
    mut fn extend<I: IntoIterator<Item = T>>(items: take I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { self.push(item) }, none => { break } }
        }
    }
}
impl<T: Ord> BinaryHeap<T> implements FromIterator<T> {
    static fn from_iter<I: IntoIterator<Item = T>>(items: take I): BinaryHeap<T> {
        var out = new::<T>()
        out.extend(items)
        out
    }
}
