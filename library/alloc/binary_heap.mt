import package.core.iter.{Iterator, BidirectionalIterator, ExactSizeIterator, OwnedIterable, Iterable, FromItems, ExtendItems}
import package.core.clone.Clone
import package.core.default.Default
import package.core.fmt
import super.alloc.{Allocator, Global, AllocError, PushError}
import super.vec.List
import package.core.cmp.{Ord, Ordering}
import package.core.ops.{Deref, DerefMut}

copy type HeapRetainEntry {
    index: usize
    keep: bool
}

copy type HeapAppendEntry {
    index: usize
    visited: bool
}

// Max-heap on a `List`.
pub type BinaryHeap<T, A: Allocator = Global> { data: List<T, A> }
pub type Iter<region r, T> { items: (read [T] from r)?; front: usize; back: usize }
pub type PeekMut<region r, T: Ord, A: Allocator> {
    queue: mut BinaryHeap<T, A> from r
    drop { sift_down(mut *self.queue, 0usize) }
}

fn sift_down<T: Ord, A: Allocator>(mut queue: BinaryHeap<T, A>, start: usize): Unit {
    let n = queue.data.len()
    if start >= n { return () }
    // Compare first so a panicking comparison does not leave a partial sift.
    var path = [0usize; 64]
    var depth = 0usize
    let origin = start
    var node = origin
    while true {
        let left = node * 2usize + 1usize
        if left >= n { break }
        var child = left
        if left + 1usize < n && queue.data[left + 1usize].cmp(queue.data[left]).is_gt() {
            child = left + 1usize
        }
        if queue.data[child].cmp(queue.data[origin]).is_gt() {
            path[depth] = child
            depth += 1usize
            node = child
        } else {
            break
        }
    }
    node = origin
    var i = 0usize
    while i < depth {
        let child = path[i]
        queue.data.swap(node, child)
        node = child
        i += 1usize
    }
}

fn append_order<T: Ord, A: Allocator>(
    read left: BinaryHeap<T, A>,
    read right: BinaryHeap<T, A>,
    left_len: usize,
    a: usize,
    b: usize
): Ordering {
    if a < left_len {
        if b < left_len {
            left.data[a].cmp(left.data[b])
        } else {
            left.data[a].cmp(right.data[b - left_len])
        }
    } else {
        if b < left_len {
            right.data[a - left_len].cmp(left.data[b])
        } else {
            right.data[a - left_len].cmp(right.data[b - left_len])
        }
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

pub fn new_in<T, A: Allocator>(take a: A): BinaryHeap<T, A> { BinaryHeap(super.vec.new_in<T, A>(a)) }
pub fn new<T>(): BinaryHeap<T> { new_in(Global()) }
pub fn try_with_capacity_in<T, A: Allocator>(n: usize, take a: A): BinaryHeap<T, A> throws AllocError {
    BinaryHeap(try super.vec.try_with_capacity_in<T, A>(n, take a))
}
pub fn with_capacity_in<T, A: Allocator>(n: usize, take a: A): BinaryHeap<T, A> {
    BinaryHeap(super.vec.with_capacity_in<T, A>(n, take a))
}
pub fn try_with_capacity<T>(n: usize): BinaryHeap<T> throws AllocError {
    try try_with_capacity_in<T, Global>(n, Global())
}
pub fn with_capacity<T>(n: usize): BinaryHeap<T> { with_capacity_in(n, Global()) }

extend<T: Ord, A: Allocator + Default> BinaryHeap<T, A> implements Default {
    static fn default(): BinaryHeap<T, A> { new_in(A.(Default).default()) }
}

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
    mut fn push_reserved(take value: T): Unit {
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
    pub mut fn try_push(take value: T): Unit throws PushError<T> {
        match capture self.data.try_reserve(1usize) {
            success(_) => {},
            failure(error) => { throw PushError(value, error) }
        }
        self.push_reserved(value)
    }
    pub mut fn push(take value: T): Unit {
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
    /// Visits every original item once. Predicate/comparison panic does not move/remove items.
    /// Uses O(n) time and O(n) Global scratch storage when an item is rejected.
    pub mut fn retain<F: mut fn(read T): bool>(take keep: F): Unit {
        var predicate = take keep
        let n = self.data.len()
        var entries = super.vec.new<HeapRetainEntry>()
        var index = 0usize
        while index < n {
            let keep_current = predicate(self.data[index])
            if !keep_current {
                entries.reserve(n)
                var previous = 0usize
                while previous < index {
                    entries.push(HeapRetainEntry(previous, true))
                    previous += 1usize
                }
                entries.push(HeapRetainEntry(index, false))
                index += 1usize
                break
            }
            index += 1usize
        }
        if entries.is_empty() { return () }
        while index < n {
            entries.push(HeapRetainEntry(index, predicate(self.data[index])))
            index += 1usize
        }

        var first_rejected = 0usize
        var end = n
        while first_rejected < end {
            if entries[first_rejected].keep {
                first_rejected += 1usize
            } else {
                end -= 1usize
                entries.swap(first_rejected, end)
            }
        }

        let retained = first_rejected
        var start = retained / 2usize
        while start > 0usize {
            start -= 1usize
            var node = start
            while true {
                let left = node * 2usize + 1usize
                if left >= retained { break }
                var child = left
                if left + 1usize < retained &&
                    self.data[entries[left + 1usize].index].cmp(
                        self.data[entries[left].index]
                    ).is_gt() {
                    child = left + 1usize
                }
                if self.data[entries[child].index].cmp(
                    self.data[entries[node].index]
                ).is_gt() {
                    entries.swap(node, child)
                    node = child
                } else {
                    break
                }
            }
        }

        // Convert destination-to-source order into source-to-destination in
        // place, using the now-unused keep bit to mark completed cycles.
        index = 0usize
        while index < n {
            entries[index].keep = false
            index += 1usize
        }
        index = 0usize
        while index < n {
            if entries[index].keep {
                index += 1usize
                continue
            }
            var current = index
            var next = entries[current].index
            while next != index {
                let following = entries[next].index
                entries[next].index = current
                entries[next].keep = true
                current = next
                next = following
            }
            entries[index].index = current
            entries[index].keep = true
            index += 1usize
        }

        index = 0usize
        while index < n {
            while entries[index].index != index {
                let other = entries[index].index
                self.data.swap(index, other)
                entries.swap(index, other)
            }
            index += 1usize
        }
        self.data.truncate(retained)
    }
    pub mut fn append(mut other: BinaryHeap<T, A>): Unit {
        let left_len = self.data.len()
        let right_len = other.data.len()
        if right_len == 0usize { return () }
        if left_len == 0usize {
            self.data.append(mut other.data)
            return ()
        }
        let total = match left_len.checked_add(right_len) {
            present(n) => n,
            none => super.alloc.panic_precondition()
        }

        // Keep both heaps unchanged if allocation or Ord panics. The index
        // heap is the final order, computed before moving either collection.
        self.data.reserve(right_len)
        var order = super.vec.new<HeapAppendEntry>()
        order.reserve(total)
        var index = 0usize
        while index < total {
            order.push(HeapAppendEntry(index, false))
            index += 1usize
        }

        var start = total / 2usize
        while start > 0usize {
            start -= 1usize
            var node = start
            while true {
                let left = node * 2usize + 1usize
                if left >= total { break }
                var child = left
                if left + 1usize < total &&
                    append_order(
                        read self,
                        read other,
                        left_len,
                        order[left + 1usize].index,
                        order[left].index
                    ).is_gt() {
                    child = left + 1usize
                }
                if append_order(
                    read self,
                    read other,
                    left_len,
                    order[child].index,
                    order[node].index
                ).is_gt() {
                    order.swap(node, child)
                    node = child
                } else {
                    break
                }
            }
        }

        self.data.append(mut other.data)
        // order[destination] names its source slot. Each permutation cycle is
        // applied with swaps, so this commit phase cannot invoke user code.
        index = 0usize
        while index < total {
            if order[index].visited {
                index += 1usize
                continue
            }
            var current = index
            var next = order[current].index
            while next != index {
                self.data.swap(current, next)
                order[current].visited = true
                current = next
                next = order[current].index
            }
            order[current].visited = true
            index += 1usize
        }
    }
    pub mut fn clear(): Unit { self.data.clear() }
    pub mut fn drain(): super.vec.Drain<region self, T, A> {
        let count = self.data.len()
        self.data.drain(0usize..count)
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

extend<T: Ord, A: Allocator> BinaryHeap<T, A> implements package.core.convert.From<List<T, A>> {
    static fn from(take items: List<T, A>): BinaryHeap<T, A> {
        var out = BinaryHeap(items)
        var i = out.data.len() / 2usize
        while i != 0usize {
            i -= 1usize
            sift_down(mut out, i)
        }
        out
    }
}

extend<T: Ord, const N: usize> BinaryHeap<T> implements package.core.convert.From<[T; N]> {
    static fn from(take items: [T; N]): BinaryHeap<T> {
        let list = super.vec.List<T>.(package.core.convert.From<[T; N]>).from(items)
        BinaryHeap<T>.(package.core.convert.From<super.vec.List<T>>).from(take list)
    }
}

// Iteration is in heap (storage) order, not sorted order.
extend<T, A: Allocator> BinaryHeap<T, A> implements Iterable {
    type Item = T
    type Iter<region r> = Iter<region r, T>
    fn iter<region r>(receiver read self: Self from r): Iter<region r, T> {
        Iter(present(self.data.as_slice()), 0usize, self.data.len())
    }
}
extend<region r, T> Iter<region r, T> implements Iterator {
    type Item = read T from r
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.front
        (remaining, present(remaining))
    }
    mut fn next(): (read T from r)? {
        if self.front >= self.back { return none }
        let index = self.front
        self.front += 1usize
        match read self.items {
            present(items) => present(read items[index]),
            none => none
        }
    }
}
extend<region r, T> Iter<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (read T from r)? {
        if self.front >= self.back { return none }
        self.back -= 1usize
        match read self.items {
            present(items) => present(read items[self.back]),
            none => none
        }
    }
}
extend<region r, T> Iter<region r, T> implements ExactSizeIterator {}
extend<region r, T> Iter<region r, T> implements Clone {
    fn clone(): Iter<region r, T> { Iter(self.items, self.front, self.back) }
}
extend<region r, T> Iter<region r, T> implements Default {
    static fn default(): Iter<region r, T> { Iter(none, 0usize, 0usize) }
}
extend<region r, T: fmt.Debug> Iter<region r, T> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("Iter(")
        try f.debug_open("[")
        var index = self.front
        var first = true
        while index < self.back {
            match read self.items {
                present(items) => {
                    try f.debug_item_start(first)
                    try T.(fmt.Debug).fmt(items[index], mut f)
                    try f.debug_item_end()
                    first = false
                },
                none => { break }
            }
            index += 1usize
        }
        try f.debug_close("]", self.front == self.back)
        try f.write_str(")")
    }
}

extend<T, A: Allocator> BinaryHeap<T, A> implements OwnedIterable {
    type Item = T
    type IntoIter = super.vec.IntoIter<T, A>
    fn into_iter(receiver take self: Self): super.vec.IntoIter<T, A> {
        self.into_vec().into_iter()
    }
}

extend<T: Clone, A: Allocator + Clone> BinaryHeap<T, A> implements Clone {
    fn clone(): BinaryHeap<T, A> { BinaryHeap(self.data.clone()) }
}
// Elements appear in heap (storage) order.
extend<T: fmt.Debug, A: Allocator> BinaryHeap<T, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try fmt.debug_slice(self.data.as_slice(), mut f)
    }
}
extend<T: Ord, A: Allocator> BinaryHeap<T, A> implements ExtendItems<T> {
    mut fn extend<I: OwnedIterable<Item = T>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { self.push(item) }, none => { break } }
        }
    }
}
extend<T: Ord> BinaryHeap<T> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(take items: I): BinaryHeap<T> {
        var out = new<T>()
        out.extend(items)
        out
    }
}

extend<T, A: Allocator> List<T, A> implements package.core.convert.From<BinaryHeap<T, A>> {
    static fn from(take source: BinaryHeap<T, A>): List<T, A> { source.into_vec() }
}
