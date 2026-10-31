import super.cmp.{PartialEq, Ord, Ordering}
import super.iter.{Iterator, BidirectionalIterator, Iterable, MutableIterable}

copy type Raw { data: ptr<read u8>; len: usize }

pub fn data(bytes: read [u8]): ptr<read u8> {
    let fat = core.ptr.from_ref(bytes)
    let raw = unsafe { core.mem.transmute<Raw>(fat) }
    raw.data
}

// Safety: start <= end <= bytes.len().
pub unsafe fn subslice_unchecked(bytes: read [u8], start: usize, end: usize): read [u8] from bytes {
    let raw = Raw(data(bytes).add(start), end - start)
    let fat = unsafe { core.mem.transmute<ptr<read [u8]>>(raw) }
    unsafe { read *fat }
}

pub fn subslice(bytes: read [u8], start: usize, end: usize): (read [u8] from bytes)? {
    if start <= end && end <= bytes.len() {
        present(unsafe { subslice_unchecked(bytes, start, end) })
    } else {
        none
    }
}

copy type RawParts<T> { data: ptr<read T>; len: usize }
copy type RawPartsMut<T> { data: ptr<mut T>; len: usize }

// Safety: `data` is valid for reads of `len` initialized elements for all of
// region `r`, is aligned, and no exclusive access overlaps it during `r`.
pub unsafe fn from_raw_parts<region r, T>(data: ptr<read T>, len: usize): read [T] from r {
    let raw = RawParts(data, len)
    let fat = unsafe { core.mem.transmute<ptr<read [T]>>(raw) }
    unsafe { read *fat }
}

// Safety: as `from_raw_parts`, for reads and writes, with no other access to
// the elements during `r`.
pub unsafe fn from_raw_parts_mut<region r, T>(data: ptr<mut T>, len: usize): mut [T] from r {
    let raw = RawPartsMut(data, len)
    let fat = unsafe { core.mem.transmute<ptr<mut [T]>>(raw) }
    unsafe { mut *fat }
}

copy type RawMut<T> { data: ptr<mut T>; len: usize }

// The fat slice pointer is represented by its data pointer and length here.
fn mutable_data_pointer<T>(xs: mut [T]): ptr<mut T> {
    let fat = core.ptr.from_mut(xs)
    let raw = unsafe { core.mem.transmute<RawMut<T>>(fat) }
    raw.data
}

// Safety: `index < xs.len()`.
unsafe fn element<T>(xs: mut [T], index: usize): ptr<mut T> {
    mutable_data_pointer(xs).add(index)
}

extend<T> [T] {
    pub fn is_empty(): bool { self.len() == 0usize }
    pub fn get(index: usize): (read T from self)? {
        if index < self.len() { present(read self[index]) } else { none }
    }
    pub mut fn get_mut(index: usize): (mut T from self)? {
        if index < self.len() { present(mut self[index]) } else { none }
    }
    pub fn first(): (read T from self)? { self.get(0usize) }
    pub fn last(): (read T from self)? {
        if self.len() == 0usize { none } else { self.get(self.len() - 1usize) }
    }
    pub mut fn first_mut(): (mut T from self)? { self.get_mut(0usize) }
    pub mut fn last_mut(): (mut T from self)? {
        if self.len() == 0usize { none } else { self.get_mut(self.len() - 1usize) }
    }
    pub mut fn swap(a: usize, b: usize) {
        if a >= self.len() || b >= self.len() { super.panic.panic("swap index out of bounds") }
        if a != b {
            unsafe { core.ptr.swap(element<T>(mut self, a), element<T>(mut self, b)) }
        }
    }
    pub mut fn reverse() {
        var i = 0usize
        var j = self.len()
        while i + 1usize < j {
            j -= 1usize
            self.swap(i, j)
            i += 1usize
        }
    }
}

extend<T: PartialEq> [T] {
    pub fn contains(value: read T): bool {
        var i = 0usize
        while i < self.len() {
            if self[i] == value { return true }
            i += 1usize
        }
        false
    }
    pub fn starts_with(prefix: read [T]): bool {
        if prefix.len() > self.len() { return false }
        var i = 0usize
        while i < prefix.len() {
            if self[i] != prefix[i] { return false }
            i += 1usize
        }
        true
    }
    pub fn ends_with(suffix: read [T]): bool {
        if suffix.len() > self.len() { return false }
        let offset = self.len() - suffix.len()
        var i = 0usize
        while i < suffix.len() {
            if self[offset + i] != suffix[i] { return false }
            i += 1usize
        }
        true
    }
}

extend<T: Ord> [T] {
    // Err carries the insertion point; the slice must be sorted ascending.
    pub fn binary_search(value: read T): usize throws usize {
        var low = 0usize
        var high = self.len()
        while low < high {
            let mid = low + (high - low) / 2usize
            let order = self[mid].cmp(value)
            if order.is_lt() {
                low = mid + 1usize
            } else {
                if order.is_gt() { high = mid } else { return mid }
            }
        }
        throw low
    }
    pub fn is_sorted(): bool {
        var i = 1usize
        while i < self.len() {
            if self[i].cmp(read self[i - 1usize]).is_lt() { return false }
            i += 1usize
        }
        true
    }
    // In-place introsort: O(n log n) worst case, no allocation, NOT stable.
    pub mut fn sort_unstable() {
        introsort(mut self, fn(a: read T, b: read T): bool { a.cmp(b).is_lt() })
    }
}

extend<T> [T] {
    pub fn binary_search_by<F: fn(read T): Ordering>(compare: take F): usize throws usize {
        var low = 0usize
        var high = self.len()
        while low < high {
            let mid = low + (high - low) / 2usize
            let order = compare(read self[mid])
            if order.is_lt() {
                low = mid + 1usize
            } else {
                if order.is_gt() { high = mid } else { return mid }
            }
        }
        throw low
    }
    pub fn binary_search_by_key<K: Ord, F: fn(read T): K>(key: read K, project: take F): usize throws usize {
        var low = 0usize
        var high = self.len()
        while low < high {
            let mid = low + (high - low) / 2usize
            let current = project(read self[mid])
            let order = current.cmp(key)
            if order.is_lt() {
                low = mid + 1usize
            } else {
                if order.is_gt() { high = mid } else { return mid }
            }
        }
        throw low
    }
    pub fn partition_point<F: fn(read T): bool>(before: take F): usize {
        var low = 0usize
        var high = self.len()
        while low < high {
            let mid = low + (high - low) / 2usize
            if before(read self[mid]) {
                low = mid + 1usize
            } else {
                high = mid
            }
        }
        low
    }
    pub fn is_sorted_by<F: fn(read T, read T): Ordering>(compare: take F): bool {
        var i = 1usize
        while i < self.len() {
            if compare(read self[i - 1usize], read self[i]).is_gt() { return false }
            i += 1usize
        }
        true
    }
    pub fn is_sorted_by_key<K: Ord, F: fn(read T): K>(key: take F): bool {
        var i = 1usize
        while i < self.len() {
            let previous = key(read self[i - 1usize])
            let current = key(read self[i])
            if previous.cmp(read current).is_gt() { return false }
            i += 1usize
        }
        true
    }
}

extend<T> [T] {
    pub mut fn sort_unstable_by<F: fn(read T, read T): Ordering>(compare: take F) {
        introsort(mut self, fn(a: read T, b: read T): bool { compare(a, b).is_lt() })
    }
    pub mut fn sort_unstable_by_key<K: Ord, F: fn(read T): K>(key: take F) {
        introsort(mut self, fn(a: read T, b: read T): bool {
            let left = key(a)
            let right = key(b)
            left.cmp(read right).is_lt()
        })
    }
}

// Introsort over `less`: median-of-three quicksort, insertion sort for short
// ranges and an in-place heapsort once the depth budget (2 * log2 n) is spent.
// Pending ranges live in a fixed stack; the smaller partition is pushed and the
// larger is processed next, so at most log2 n + 1 ranges are pending.
fn introsort<T, F: fn(read T, read T): bool>(xs: mut [T], less: take F) {
    let n = xs.len()
    if n < 2usize { return }
    var budget = 0usize
    var shrinking = n
    while shrinking > 1usize { shrinking /= 2usize; budget += 2usize }
    var lows = [0usize; 80]
    var highs = [0usize; 80]
    var budgets = [0usize; 80]
    var top = 1usize
    lows[0usize] = 0usize
    highs[0usize] = n
    budgets[0usize] = budget
    while top > 0usize {
        top -= 1usize
        var lo = lows[top]
        var hi = highs[top]
        var left_budget = budgets[top]
        while hi - lo > 1usize {
            if hi - lo <= 16usize {
                var i = lo + 1usize
                while i < hi {
                    var j = i
                    while j > lo && less(read xs[j], read xs[j - 1usize]) {
                        xs.swap(j, j - 1usize)
                        j -= 1usize
                    }
                    i += 1usize
                }
                break
            }
            if left_budget == 0usize {
                let size = hi - lo
                var start = size / 2usize
                while start > 0usize {
                    start -= 1usize
                    var root = start
                    while true {
                        var child = root * 2usize + 1usize
                        if child >= size { break }
                        if child + 1usize < size && less(read xs[lo + child], read xs[lo + child + 1usize]) {
                            child += 1usize
                        }
                        if less(read xs[lo + root], read xs[lo + child]) {
                            xs.swap(lo + root, lo + child)
                            root = child
                        } else {
                            break
                        }
                    }
                }
                var end = size
                while end > 1usize {
                    end -= 1usize
                    xs.swap(lo, lo + end)
                    var root = 0usize
                    while true {
                        var child = root * 2usize + 1usize
                        if child >= end { break }
                        if child + 1usize < end && less(read xs[lo + child], read xs[lo + child + 1usize]) {
                            child += 1usize
                        }
                        if less(read xs[lo + root], read xs[lo + child]) {
                            xs.swap(lo + root, lo + child)
                            root = child
                        } else {
                            break
                        }
                    }
                }
                break
            }
            left_budget -= 1usize
            let mid = lo + (hi - lo) / 2usize
            let last = hi - 1usize
            if less(read xs[mid], read xs[lo]) { xs.swap(mid, lo) }
            if less(read xs[last], read xs[mid]) {
                xs.swap(last, mid)
                if less(read xs[mid], read xs[lo]) { xs.swap(mid, lo) }
            }
            xs.swap(lo, mid)
            var i = lo + 1usize
            var j = last
            while true {
                while i <= j && less(read xs[i], read xs[lo]) { i += 1usize }
                while i <= j && less(read xs[lo], read xs[j]) { j -= 1usize }
                if i >= j { break }
                xs.swap(i, j)
                i += 1usize
                j -= 1usize
            }
            xs.swap(lo, j)
            if j - lo < hi - (j + 1usize) {
                lows[top] = lo
                highs[top] = j
                budgets[top] = left_budget
                top += 1usize
                lo = j + 1usize
            } else {
                lows[top] = j + 1usize
                highs[top] = hi
                budgets[top] = left_budget
                top += 1usize
                hi = j
            }
        }
    }
}

// Borrowing iteration over the elements of a slice.
pub type SliceIter<region r, T> { items: read [T] from r; front: usize; back: usize }
extend<region r, T> SliceIter<region r, T> implements Iterator {
    type Item = read T from r
    mut fn next(): (read T from r)? {
        if self.front < self.back {
            let i = self.front
            self.front += 1usize
            present(read self.items[i])
        } else {
            none
        }
    }
}
extend<region r, T> SliceIter<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (read T from r)? {
        if self.front < self.back {
            self.back -= 1usize
            present(read self.items[self.back])
        } else {
            none
        }
    }
}

pub type SliceIterMut<region r, T> { items: mut [T] from r; front: usize; back: usize }
extend<region r, T> SliceIterMut<region r, T> implements Iterator {
    type Item = mut T from r
    mut fn next(): (mut T from r)? {
        if self.front < self.back {
            let i = self.front
            self.front += 1usize
            present(mut self.items[i])
        } else {
            none
        }
    }
}
extend<region r, T> SliceIterMut<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (mut T from r)? {
        if self.front < self.back {
            self.back -= 1usize
            present(mut self.items[self.back])
        } else {
            none
        }
    }
}

extend<T> [T] {
    pub fn iter(): SliceIter<region self, T> { SliceIter(read self, 0usize, self.len()) }
    pub mut fn iter_mut(): SliceIterMut<region self, T> {
        let n = self.len()
        SliceIterMut(mut self, 0usize, n)
    }
}

extend<T> [T] implements Iterable {
    type Item = T
    type Iter<region r> = SliceIter<region r, T>
    fn iter<region r>(receiver self: read Self from r): SliceIter<region r, T> {
        self.iter()
    }
}

extend<T> [T] implements MutableIterable {
    type Item = T
    type IterMut<region r> = SliceIterMut<region r, T>
    fn iter_mut<region r>(receiver self: mut Self from r): SliceIterMut<region r, T> {
        self.iter_mut()
    }
}

// Copy-valued iteration over the bytes of a slice: yields `u8` while holding a
// read loan on the slice; allocates nothing.
pub type SliceBytes<region r> { items: read [u8] from r; front: usize; back: usize }
extend<region r> SliceBytes<region r> implements Iterator {
    type Item = u8
    mut fn next(): u8? {
        if self.front < self.back {
            let value = self.items[self.front]
            self.front += 1usize
            present(value)
        } else {
            none
        }
    }
}
extend<region r> SliceBytes<region r> implements BidirectionalIterator {
    mut fn next_back(): u8? {
        if self.front < self.back {
            self.back -= 1usize
            present(self.items[self.back])
        } else {
            none
        }
    }
}

extend [u8] {
    pub fn bytes(): SliceBytes<region self> { SliceBytes(read self, 0usize, self.len()) }
}

copy type RawRead<T> { data: ptr<read T>; len: usize }

// Safety: start <= end <= xs.len().
unsafe fn sub<T>(xs: read [T], start: usize, end: usize): read [T] from xs {
    let fat = core.ptr.from_ref(xs)
    let raw = unsafe { core.mem.transmute<RawRead<T>>(fat) }
    let part = unsafe { core.mem.transmute<ptr<read [T]>>(RawRead(raw.data.add(start), end - start)) }
    unsafe { read *part }
}

extend<T> [T] {
    pub fn split_at(mid: usize): (read [T] from self, read [T] from self) {
        if mid > self.len() { super.panic.panic("split index out of bounds") }
        (unsafe { sub<T>(read self, 0usize, mid) }, unsafe { sub<T>(read self, mid, self.len()) })
    }
    pub fn split_at_checked(mid: usize): (read [T] from self, read [T] from self)? {
        if mid > self.len() { return none }
        present((unsafe { sub<T>(read self, 0usize, mid) }, unsafe { sub<T>(read self, mid, self.len()) }))
    }
    pub mut fn split_at_mut(mid: usize): (mut [T] from self, mut [T] from self) {
        if mid > self.len() { super.panic.panic("split index out of bounds") }
        let n = self.len()
        let base = mutable_data_pointer(mut self)
        // The guard keeps both ranges within the initialized slice and disjoint.
        let left = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base, mid)) }
        let right = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base.add(mid), n - mid)) }
        (unsafe { mut *left }, unsafe { mut *right })
    }
    pub mut fn split_at_mut_checked(mid: usize): (mut [T] from self, mut [T] from self)? {
        if mid > self.len() { return none }
        let n = self.len()
        let base = mutable_data_pointer(mut self)
        // The guard keeps both ranges within the initialized slice and disjoint.
        let left = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base, mid)) }
        let right = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base.add(mid), n - mid)) }
        present((unsafe { mut *left }, unsafe { mut *right }))
    }
}

extend<T: Copy> [T] {
    pub mut fn fill(value: T) {
        var i = 0usize
        while i < self.len() {
            self[i] = value
            i += 1usize
        }
    }
    // Panics when the lengths differ.
    pub mut fn copy_from_slice(source: read [T]) {
        if source.len() != self.len() { super.panic.panic("copy_from_slice length mismatch") }
        var i = 0usize
        while i < source.len() {
            self[i] = source[i]
            i += 1usize
        }
    }
}

extend<T> [T] {
    pub fn subslice(start: usize, end: usize): (read [T] from self)? {
        if start <= end && end <= self.len() { present(unsafe { sub<T>(read self, start, end) }) } else { none }
    }
    // The `index`-th window of `size` overlapping elements, if it exists.
    pub fn window(index: usize, size: usize): (read [T] from self)? {
        if size == 0usize || index > self.len() || size > self.len() - index { return none }
        self.subslice(index, index + size)
    }
    // The `index`-th chunk of `size` elements; the last chunk may be shorter.
    pub fn chunk(index: usize, size: usize): (read [T] from self)? {
        if size == 0usize { return none }
        if self.len() == 0usize || index > (self.len() - 1usize) / size { return none }
        let start = index * size
        let end = if self.len() - start < size { self.len() } else { start + size }
        self.subslice(start, end)
    }
}
