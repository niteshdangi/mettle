import package.core.iter.{Iterator, OwnedIterable, Iterable, FromItems, ExtendItems}
import package.core.clone.Clone
import package.core.fmt
import package.core.slice.SliceIter
import super.alloc.{Allocator, Global, AllocError}
import super.vec.List
import package.core.cmp.Ord

// Max-heap on a `List`.
pub type BinaryHeap<T, A: Allocator = Global> { data: List<T, A> }

pub fn new_in<T, A: Allocator>(a: take A): BinaryHeap<T, A> { BinaryHeap(super.vec.new_in<T, A>(a)) }
pub fn new<T>(): BinaryHeap<T> { new_in(Global()) }

extend<T: Ord, A: Allocator> BinaryHeap<T, A> {
    pub fn len(): usize { self.data.len() }
    pub fn is_empty(): bool { self.data.is_empty() }
    pub fn peek(): (read T from self)? { self.data.get(0usize) }
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
    pub mut fn try_push(value: take T): Unit throws AllocError {
        try self.data.try_reserve(1usize)
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
    fn fmt<W: fmt.Write>(f: mut fmt.Formatter<W>): Unit throws fmt.Error {
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
