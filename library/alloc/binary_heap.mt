import package.core.iter.{Iterator, OwnedIterable, Iterable, FromItems, ExtendItems}
import package.core.clone.Clone
import package.core.fmt
import package.core.slice.SliceIter
import super.alloc.{Allocator, Global, AllocError, PushError}
import super.vec.List
import package.core.cmp.Ord
import package.core.ops.{Deref, DerefMut}

// Max-heap on a `List`.
pub type BinaryHeap<T, A: Allocator = Global> { data: List<T, A> }
pub type PeekMut<region r, T: Ord, A: Allocator> {
    queue: mut BinaryHeap<T, A> from r
    drop { sift_down(mut *self.queue) }
}

fn sift_down<T: Ord, A: Allocator>(queue: mut BinaryHeap<T, A>): Unit {
    let n = queue.data.len()
    if n < 2usize { return () }
    // Compare first so a panicking comparison does not leave a partial sift.
    var path = [0usize; 64]
    var depth = 0usize
    var node = 0usize
    while true {
        let left = node * 2usize + 1usize
        if left >= n { break }
        var child = left
        if left + 1usize < n && queue.data[left + 1usize].cmp(queue.data[left]).is_gt() {
            child = left + 1usize
        }
        if queue.data[child].cmp(queue.data[0usize]).is_gt() {
            path[depth] = child
            depth += 1usize
            node = child
        } else {
            break
        }
    }
    node = 0usize
    var i = 0usize
    while i < depth {
        let child = path[i]
        queue.data.swap(node, child)
        node = child
        i += 1usize
    }
}

extend<region r, T: Ord, A: Allocator> PeekMut<region r, T, A> implements Deref {
    type Target = T
    fn deref(): read T from self { unsafe { read *self.queue.data.as_ptr() } }
}
extend<region r, T: Ord, A: Allocator> PeekMut<region r, T, A> implements DerefMut {
    type Target = T
    mut fn deref_mut(): mut T from self { unsafe { mut *self.queue.data.as_mut_ptr() } }
}

pub fn new_in<T, A: Allocator>(a: take A): BinaryHeap<T, A> { BinaryHeap(super.vec.new_in<T, A>(a)) }
pub fn new<T>(): BinaryHeap<T> { new_in(Global()) }
pub fn try_with_capacity_in<T, A: Allocator>(n: usize, a: take A): BinaryHeap<T, A> throws AllocError {
    BinaryHeap(try super.vec.try_with_capacity_in<T, A>(n, take a))
}
pub fn with_capacity_in<T, A: Allocator>(n: usize, a: take A): BinaryHeap<T, A> {
    BinaryHeap(super.vec.with_capacity_in<T, A>(n, take a))
}
pub fn try_with_capacity<T>(n: usize): BinaryHeap<T> throws AllocError {
    try try_with_capacity_in<T, Global>(n, Global())
}
pub fn with_capacity<T>(n: usize): BinaryHeap<T> { with_capacity_in(n, Global()) }

extend<T, A: Allocator> BinaryHeap<T, A> {
    pub fn len(): usize { self.data.len() }
    pub fn capacity(): usize { self.data.capacity() }
    pub fn is_empty(): bool { self.data.is_empty() }
    pub mut fn try_reserve(additional: usize): Unit throws AllocError {
        try self.data.try_reserve(additional)
    }
    pub mut fn reserve(additional: usize): Unit { self.data.reserve(additional) }
    pub mut fn try_reserve_exact(additional: usize): Unit throws AllocError {
        try self.data.try_reserve_exact(additional)
    }
    pub mut fn reserve_exact(additional: usize): Unit {
        self.data.reserve_exact(additional)
    }
    pub mut fn shrink_to_fit(): Unit { self.data.shrink_to_fit() }
    pub mut fn shrink_to(min_capacity: usize): Unit {
        let len = self.data.len()
        let capacity = self.data.capacity()
        if min_capacity > len || min_capacity >= capacity { return () }
        self.data.shrink_to_fit()
    }
}

extend<T: Ord, A: Allocator> BinaryHeap<T, A> {
    pub fn peek(): (read T from self)? { self.data.get(0usize) }
    pub mut fn peek_mut(): PeekMut<region self, T, A>? {
        if self.data.is_empty() { return none }
        present(PeekMut(mut self))
    }
    pub fn as_slice(): read [T] from self { self.data.as_slice() }

    // Compare the full path before changing the heap. If Ord panics, the
    // caller has not yet inserted the value and the existing heap is intact.
    mut fn push_reserved(value: take T): Unit {
        let last = self.data.len()
        var destination = last
        while destination > 0usize {
            let parent = (destination - 1usize) / 2usize
            if value.cmp(self.data[parent]).is_gt() {
                destination = parent
            } else {
                break
            }
        }
        self.data.push(value)
        var i = last
        while i > destination {
            let parent = (i - 1usize) / 2usize
            self.data.swap(i, parent)
            i = parent
        }
    }
    pub mut fn try_push(value: take T): Unit throws PushError<T> {
        match capture self.data.try_reserve(1usize) {
            success(_) => {},
            failure(error) => { throw PushError(value, error) }
        }
        self.push_reserved(value)
    }
    pub mut fn push(value: take T): Unit {
        self.data.reserve(1usize)
        self.push_reserved(value)
    }
    pub mut fn pop(): T? {
        let n = self.data.len()
        if n == 0usize { return none }
        let last = n - 1usize
        // Compare the repair path before mutating; usize indices bound it to
        // at most 64 levels.
        var path = [0usize; 64]
        var depth = 0usize
        var node = 0usize
        while true {
            let left = 2usize * node + 1usize
            if left >= last { break }
            var big = left
            if left + 1usize < last && self.data[left + 1usize].cmp(self.data[left]).is_gt() {
                big = left + 1usize
            }
            if self.data[big].cmp(self.data[last]).is_gt() {
                path[depth] = big
                depth += 1usize
                node = big
            } else {
                break
            }
        }
        self.data.swap(0usize, n - 1usize)
        let top = self.data.pop()
        node = 0usize
        var i = 0usize
        while i < depth {
            let child = path[i]
            self.data.swap(node, child)
            node = child
            i += 1usize
        }
        top
    }
    pub mut fn clear(): Unit { self.data.clear() }
    pub mut fn drain(): super.vec.Drain<region self, T, A> {
        let count = self.data.len()
        self.data.drain(0usize, count)
    }

    pub take fn into_sorted_vec(): List<T, A> {
        var out = self.into_vec()
        out.sort()
        out
    }
}

extend<T, A: Allocator> BinaryHeap<T, A> {
    pub take fn into_vec(): List<T, A> {
        unsafe {
            let v = core.ptr.`read`(core.ptr.from_ref(self.data))
            core.mem.forget(take self)
            v
        }
    }
}

// Iteration is in heap (storage) order, not sorted order.
extend<T, A: Allocator> BinaryHeap<T, A> implements Iterable {
    type Item = T
    type Iter<region r> = SliceIter<region r, T>
    fn iter<region r>(receiver self: read Self from r): SliceIter<region r, T> { self.data.as_slice().iter() }
}

extend<T, A: Allocator> BinaryHeap<T, A> implements OwnedIterable {
    type Item = T
    type IntoIter = super.vec.IntoIter<T, A>
    fn into_iter(receiver self: take Self): super.vec.IntoIter<T, A> {
        self.into_vec().into_iter()
    }
}

extend<T: Clone, A: Allocator + Clone> BinaryHeap<T, A> implements Clone {
    fn clone(): BinaryHeap<T, A> { BinaryHeap(self.data.clone()) }
}
// Elements appear in heap (storage) order.
extend<T: fmt.Debug, A: Allocator> BinaryHeap<T, A> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try fmt.debug_slice(self.data.as_slice(), mut f)
    }
}
extend<T: Ord, A: Allocator> BinaryHeap<T, A> implements ExtendItems<T> {
    mut fn extend<I: OwnedIterable<Item = T>>(items: take I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { self.push(item) }, none => { break } }
        }
    }
}
extend<T: Ord> BinaryHeap<T> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(items: take I): BinaryHeap<T> {
        var out = new<T>()
        out.extend(items)
        out
    }
}
