import super.cmp.{PartialEq, Ord, Ordering}
import super.iter.{Iterator, BidirectionalIterator, ExactSizeIterator, Iterable, MutableIterable}
import super.clone.Clone

copy type Raw { data: ptr<read u8>; len: usize }

type DropValuesGuard<T> {
    p: ptr<mut T>
    n: usize
    drop {
        while self.n != 0usize {
            // Advance before dropping so unwinding never revisits this value.
            let current = self.p
            self.p = unsafe { self.p.add(1usize) }
            self.n -= 1usize
            unsafe { core.ptr.drop_in_place(current) }
        }
    }
}

// Safety: `p` points to `n` initialized, aligned `T` values that may be
// exclusively destroyed. The range remains valid until all drops complete.
pub unsafe fn drop_values<T>(p: ptr<mut T>, n: usize): Unit {
    let _guard = DropValuesGuard(p, n)
}

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
    // Safety: `index` is less than the slice length.
    pub unsafe fn get_unchecked(index: usize): read T from self {
        let raw = unsafe { core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self)) }
        unsafe { read *raw.data.add(index) }
    }
    pub mut fn get_mut(index: usize): (mut T from self)? {
        if index < self.len() { present(mut self[index]) } else { none }
    }
    // Safety: `index` is less than the slice length.
    pub mut unsafe fn get_unchecked_mut(index: usize): mut T from self {
        unsafe { mut *mutable_data_pointer(mut self).add(index) }
    }
    pub fn first(): (read T from self)? { self.get(0usize) }
    pub fn last(): (read T from self)? {
        if self.len() == 0usize { none } else { self.get(self.len() - 1usize) }
    }
    pub mut fn first_mut(): (mut T from self)? { self.get_mut(0usize) }
    pub mut fn last_mut(): (mut T from self)? {
        if self.len() == 0usize { none } else { self.get_mut(self.len() - 1usize) }
    }
    pub fn as_ptr_range(): super.iter.Range<ptr<read T>> {
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        // Safety: the slice pointer is valid through its one-past-end position.
        let end = unsafe { raw.data.add(self.len()) }
        super.iter.Range(raw.data, end)
    }
    pub mut fn as_mut_ptr_range(): super.iter.Range<ptr<mut T>> {
        let base = mutable_data_pointer(mut self)
        // Safety: the slice pointer is valid through its one-past-end position.
        let end = unsafe { base.add(self.len()) }
        super.iter.Range(base, end)
    }
    pub fn element_offset(element: read T): usize? {
        let size = core.mem.size_of<T>()
        if size == 0usize {
            if self.len() == 0usize { return none }
            return present(0usize)
        }
        let raw = unsafe { core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self)) }
        let base = raw.data as usize
        let address = core.ptr.from_ref(element) as usize
        if address < base { return none }
        let distance = address - base
        if distance % size != 0usize { return none }
        let index = distance / size
        if index >= self.len() { return none }
        present(index)
    }
    pub fn subslice_range(part: read [T]): super.iter.Range<usize>? {
        let size = core.mem.size_of<T>()
        if size == 0usize {
            if part.len() > self.len() { return none }
            return present(super.iter.Range(0usize, part.len()))
        }
        let raw = unsafe { core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self)) }
        let inner = unsafe { core.mem.transmute<RawParts<T>>(core.ptr.from_ref(part)) }
        let base = raw.data as usize
        let address = inner.data as usize
        if address < base { return none }
        let distance = address - base
        if distance % size != 0usize { return none }
        let start = distance / size
        let end = start + part.len()
        if end > self.len() { return none }
        present(super.iter.Range(start, end))
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

extend<T> [T] {
    pub fn first_chunk<const N: usize>(): (read [T; N] from self)? {
        if N > self.len() { return none }
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        // Safety: the checked length covers all N initialized elements.
        present(unsafe { read *raw.data.cast<[T; N]>() })
    }

    pub fn last_chunk<const N: usize>(): (read [T; N] from self)? {
        if N > self.len() { return none }
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        // Safety: the checked suffix contains N initialized elements.
        present(unsafe { read *raw.data.add(self.len() - N).cast<[T; N]>() })
    }

    pub fn split_first_chunk<const N: usize>(): ((read [T; N] from self), (read [T] from self))? {
        if N > self.len() { return none }
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        // Safety: the array and suffix are in-bounds parts of the source slice.
        let first = unsafe { read *raw.data.cast<[T; N]>() }
        let rest = unsafe { sub<T>(read self, N, self.len()) }
        present((first, rest))
    }

    pub fn split_last_chunk<const N: usize>(): ((read [T] from self), (read [T; N] from self))? {
        if N > self.len() { return none }
        let start = self.len() - N
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        // Safety: the prefix and array are in-bounds parts of the source slice.
        let last = unsafe { read *raw.data.add(start).cast<[T; N]>() }
        let rest = unsafe { sub<T>(read self, 0usize, start) }
        present((rest, last))
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
    pub fn strip_prefix(prefix: read [T]): (read [T] from self)? {
        if !self.starts_with(prefix) { return none }
        present(unsafe { sub<T>(read self, prefix.len(), self.len()) })
    }
    pub fn strip_suffix(suffix: read [T]): (read [T] from self)? {
        if !self.ends_with(suffix) { return none }
        present(unsafe { sub<T>(read self, 0usize, self.len() - suffix.len()) })
    }
    pub fn strip_circumfix(prefix: read [T], suffix: read [T]): (read [T] from self)? {
        match self.strip_prefix(prefix) {
            present(rest) => rest.strip_suffix(suffix),
            none => none
        }
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

extend<T: Ord> [T] {
    pub mut fn select_nth_unstable(
        nth: usize
    ): (mut [T] from self, mut T from self, mut [T] from self) {
        self.select_nth_unstable_by(nth, fn(a: read T, b: read T): Ordering { a.cmp(b) })
    }
}

extend<T> [T] {
    pub mut fn select_nth_unstable_by<F: fn(read T, read T): Ordering>(
        nth: usize,
        compare: take F
    ): (mut [T] from self, mut T from self, mut [T] from self) {
        let less = fn(a: read T, b: read T): bool { compare(a, b).is_lt() }
        let n = self.len()
        if nth >= n { super.panic.panic("selection index out of bounds") }
        var low = 0usize
        var high = n
        while high - low > 1usize {
            let mid = low + (high - low) / 2usize
            let last = high - 1usize
            if less(read self[mid], read self[low]) { self.swap(mid, low) }
            if less(read self[last], read self[mid]) {
                self.swap(last, mid)
                if less(read self[mid], read self[low]) { self.swap(mid, low) }
            }
            self.swap(mid, last)
            let pivot = last
            var lower = low
            var scan = low
            var greater = pivot
            while scan < greater {
                if less(read self[scan], read self[pivot]) {
                    self.swap(scan, lower)
                    lower += 1usize
                    scan += 1usize
                } else if less(read self[pivot], read self[scan]) {
                    greater -= 1usize
                    self.swap(scan, greater)
                } else {
                    scan += 1usize
                }
            }
            self.swap(greater, pivot)
            let equal_end = greater + 1usize
            if nth < lower {
                high = lower
            } else if nth >= equal_end {
                low = equal_end
            } else {
                break
            }
        }
        let base = mutable_data_pointer(mut self)
        let left = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base, nth)) }
        let middle = unsafe { base.add(nth) }
        let right = unsafe {
            core.mem.transmute<ptr<mut [T]>>(RawMut(middle.add(1usize), n - nth - 1usize))
        }
        (unsafe { mut *left }, unsafe { mut *middle }, unsafe { mut *right })
    }

    pub mut fn select_nth_unstable_by_key<K: Ord, F: fn(read T): K>(
        nth: usize,
        key: take F
    ): (mut [T] from self, mut T from self, mut [T] from self) {
        self.select_nth_unstable_by(nth, fn(a: read T, b: read T): Ordering {
            key(a).cmp(key(b))
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
extend<region r, T> SliceIter<region r, T> {
    pub fn as_slice(): read [T] from r {
        self.items.split_at(self.back).0.split_at(self.front).1
    }
    fn size_hint(): (usize, usize?) {
        let count = self.back - self.front
        (count, present(count))
    }
}
extend<region r, T> SliceIter<region r, T> implements ExactSizeIterator {
    fn len(): usize { self.back - self.front }
}
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
extend<region r, T> SliceIterMut<region r, T> {
    pub fn as_slice(): read [T] from r {
        let items: read [T] = read self.items
        items.split_at(self.back).0.split_at(self.front).1
    }
    fn size_hint(): (usize, usize?) {
        let count = self.back - self.front
        (count, present(count))
    }
}
extend<region r, T> SliceIterMut<region r, T> implements ExactSizeIterator {
    fn len(): usize { self.back - self.front }
}
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

extend<T> [T] {
    pub fn align_to<U>(): (read [T] from self, read [U] from self, read [T] from self) {
        let raw = unsafe { core.mem.transmute<RawRead<T>>(core.ptr.from_ref(self)) }
        let len = self.len()
        let size_t = core.mem.size_of<T>()
        let size_u = core.mem.size_of<U>()
        let align = core.mem.align_of<U>()
        let prefix = match elements_until_aligned(raw.data as usize, size_t, align, len) {
            present(n) => n,
            none => {
                let middle = unsafe { typed_slice<T, U>(read self, dangling_read<U>(), 0usize) }
                let tail = unsafe { sub<T>(read self, len, len) }
                return (read self, middle, tail)
            }
        }
        if size_u != 0usize && size_t == 0usize {
            let middle = unsafe { typed_slice<T, U>(read self, dangling_read<U>(), 0usize) }
            let tail = unsafe { sub<T>(read self, len, len) }
            return (read self, middle, tail)
        }
        let head = unsafe { sub<T>(read self, 0usize, prefix) }
        if size_u == 0usize {
            let middle = unsafe {
                typed_slice<T, U>(read self, raw.data.add(prefix).cast<U>(),
                                  0xffffffffffffffffusize)
            }
            let tail = unsafe { sub<T>(read self, prefix, len) }
            return (head, middle, tail)
        }
        let rest_bytes = (len - prefix) * size_t
        let step = match byte_step(size_u, size_t) {
            present(value) => value,
            none => {
                let middle = unsafe { typed_slice<T, U>(read self, dangling_read<U>(), 0usize) }
                let tail = unsafe { sub<T>(read self, len, len) }
                return (read self, middle, tail)
            }
        }
        if step == 0usize {
            let middle = unsafe { typed_slice<T, U>(read self, dangling_read<U>(), 0usize) }
            let tail = unsafe { sub<T>(read self, prefix, len) }
            return (head, middle, tail)
        }
        let mid_bytes = (rest_bytes / step) * step
        let middle = unsafe {
            typed_slice<T, U>(read self, raw.data.add(prefix).cast<U>(), mid_bytes / size_u)
        }
        let tail = unsafe { sub<T>(read self, prefix + mid_bytes / size_t, len) }
        (head, middle, tail)
    }
    pub mut fn align_to_mut<U>(): (mut [T] from self, mut [U] from self, mut [T] from self) {
        let base = mutable_data_pointer(mut self)
        let len = self.len()
        let size_t = core.mem.size_of<T>()
        let size_u = core.mem.size_of<U>()
        let align = core.mem.align_of<U>()
        let prefix = match elements_until_aligned(base as usize, size_t, align, len) {
            present(n) => n,
            none => {
                let middle = unsafe { typed_slice_mut<T, U>(mut self, dangling_mut<U>(), 0usize) }
                let tail = unsafe { sub_mut<T>(mut self, len, len) }
                return (mut self, middle, tail)
            }
        }
        if size_u != 0usize && size_t == 0usize {
            let middle = unsafe { typed_slice_mut<T, U>(mut self, dangling_mut<U>(), 0usize) }
            let tail = unsafe { sub_mut<T>(mut self, len, len) }
            return (mut self, middle, tail)
        }
        let head = unsafe { sub_mut<T>(mut self, 0usize, prefix) }
        if size_u == 0usize {
            let middle = unsafe {
                typed_slice_mut<T, U>(mut self, base.add(prefix).cast<U>(),
                                      0xffffffffffffffffusize)
            }
            let tail = unsafe { sub_mut<T>(mut self, prefix, len) }
            return (head, middle, tail)
        }
        let rest_bytes = (len - prefix) * size_t
        let step = match byte_step(size_u, size_t) {
            present(value) => value,
            none => {
                let middle = unsafe { typed_slice_mut<T, U>(mut self, dangling_mut<U>(), 0usize) }
                let tail = unsafe { sub_mut<T>(mut self, len, len) }
                return (mut self, middle, tail)
            }
        }
        if step == 0usize {
            let middle = unsafe { typed_slice_mut<T, U>(mut self, dangling_mut<U>(), 0usize) }
            let tail = unsafe { sub_mut<T>(mut self, prefix, len) }
            return (head, middle, tail)
        }
        let mid_bytes = (rest_bytes / step) * step
        let middle = unsafe {
            typed_slice_mut<T, U>(mut self, base.add(prefix).cast<U>(), mid_bytes / size_u)
        }
        let tail = unsafe { sub_mut<T>(mut self, prefix + mid_bytes / size_t, len) }
        (head, middle, tail)
    }
}

extend<T: Copy> [T] {
    pub mut fn write_copy_of_slice(src: read [T]): Unit {
        if self.len() != src.len() {
            super.panic.panic("destination and source slices have different lengths")
        }
        if self.len() == 0usize { return () }
        let source = unsafe { core.mem.transmute<RawRead<T>>(core.ptr.from_ref(src)) }
        unsafe { core.ptr.`copy`(source.data, mutable_data_pointer(mut self), self.len()) }
    }
}

extend<T: Clone> [T] {
    pub mut fn write_clone_of_slice(src: read [T]): Unit {
        if self.len() != src.len() {
            super.panic.panic("destination and source slices have different lengths")
        }
        var index = 0usize
        while index < self.len() {
            self[index] = src[index].clone()
            index += 1usize
        }
    }
}

extend<T> [core.mem.MaybeUninit<T>] {
    // Safety: every element is initialized.
    pub unsafe fn assume_init_ref(): read [T] from self {
        let raw = unsafe {
            core.mem.transmute<RawRead<core.mem.MaybeUninit<T>>>(core.ptr.from_ref(self))
        }
        unsafe { typed_slice<core.mem.MaybeUninit<T>, T>(read self, raw.data.cast<T>(), self.len()) }
    }
    // Safety: every element is initialized.
    pub mut unsafe fn assume_init_mut(): mut [T] from self {
        let base = mutable_data_pointer(mut self)
        unsafe { typed_slice_mut<core.mem.MaybeUninit<T>, T>(mut self, base.cast<T>(), self.len()) }
    }
    // Safety: every element is initialized. Each value is dropped once.
    pub mut unsafe fn assume_init_drop(): Unit {
        var index = 0usize
        while index < self.len() {
            unsafe { self[index].assume_init_drop() }
            index += 1usize
        }
    }
}

extend<T, const N: usize> [core.mem.MaybeUninit<T>; N] {
    // Safety: every element is initialized. The array is consumed.
    pub take unsafe fn assume_init(): [T; N] {
        let pointer = core.ptr.from_ref(self).cast<[T; N]>()
        let value = unsafe { core.ptr.`read`(pointer) }
        core.mem.forget(take self)
        value
    }
}

copy type RawRead<T> { data: ptr<read T>; len: usize }

fn dangling_read<T>(): ptr<read T> {
    let align = core.mem.align_of<T>()
    unsafe { core.mem.transmute<ptr<read T>>(align) }
}

fn dangling_mut<T>(): ptr<mut T> {
    let align = core.mem.align_of<T>()
    unsafe { core.mem.transmute<ptr<mut T>>(align) }
}

fn gcd_usize(a: usize, b: usize): usize {
    var x = a
    var y = b
    while y != 0usize {
        let next = x % y
        x = y
        y = next
    }
    x
}

// Smallest `n <= len` such that `address + n * size` is aligned, if one exists.
fn elements_until_aligned(address: usize, size: usize, align: usize, len: usize): usize? {
    if align == 0usize { return none }
    var n = 0usize
    var steps = 0usize
    while n <= len && steps < align {
        if (address + n * size) % align == 0usize { return present(n) }
        n += 1usize
        steps += 1usize
    }
    none
}

// The middle of `align_to` consumes whole elements of both types.
fn byte_step(size_u: usize, size_t: usize): usize? {
    let divisor = gcd_usize(size_u, size_t)
    if divisor == 0usize { return present(0usize) }
    (size_u / divisor).checked_mul(size_t)
}

// Safety: `data` is valid for `len` elements of `U` for the same region as `xs`.
unsafe fn typed_slice<T, U>(xs: read [T], data: ptr<read U>, len: usize): read [U] from xs {
    let part = unsafe { core.mem.transmute<ptr<read [U]>>(RawRead(data, len)) }
    unsafe { read *part }
}

// Safety: `data` is valid for exclusive access to `len` elements of `U`.
unsafe fn typed_slice_mut<T, U>(xs: mut [T], data: ptr<mut U>, len: usize): mut [U] from xs {
    let part = unsafe { core.mem.transmute<ptr<mut [U]>>(RawMut(data, len)) }
    unsafe { mut *part }
}

// Safety: start <= end <= xs.len().
unsafe fn sub<T>(xs: read [T], start: usize, end: usize): read [T] from xs {
    let fat = core.ptr.from_ref(xs)
    let raw = unsafe { core.mem.transmute<RawRead<T>>(fat) }
    let part = unsafe { core.mem.transmute<ptr<read [T]>>(RawRead(raw.data.add(start), end - start)) }
    unsafe { read *part }
}

// Safety: start <= end <= xs.len().
unsafe fn sub_mut<T>(xs: mut [T], start: usize, end: usize): mut [T] from xs {
    let base = mutable_data_pointer(mut xs)
    let part = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base.add(start), end - start)) }
    unsafe { mut *part }
}

// Safety: `index + N <= xs.len()`.
unsafe fn array_at<T, const N: usize>(xs: read [T], index: usize): read [T; N] from xs {
    let fat = core.ptr.from_ref(xs)
    let raw = unsafe { core.mem.transmute<RawRead<T>>(fat) }
    unsafe { read *raw.data.add(index).cast<[T; N]>() }
}

// Safety: `start + count * N <= xs.len()`.
unsafe fn array_chunks_at<T, const N: usize>(
    xs: read [T], start: usize, count: usize
): read [[T; N]] from xs {
    let fat = core.ptr.from_ref(xs)
    let raw = unsafe { core.mem.transmute<RawRead<T>>(fat) }
    let part = unsafe {
        core.mem.transmute<ptr<read [[T; N]]>>(
            RawRead(raw.data.add(start).cast<[T; N]>(), count)
        )
    }
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
    // Safety: `mid <= self.len()`.
    pub unsafe fn split_at_unchecked(mid: usize): (read [T] from self, read [T] from self) {
        (unsafe { sub<T>(read self, 0usize, mid) }, unsafe { sub<T>(read self, mid, self.len()) })
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
    // Safety: `mid <= self.len()`. The two results are disjoint.
    pub mut unsafe fn split_at_mut_unchecked(mid: usize): (mut [T] from self, mut [T] from self) {
        let n = self.len()
        let base = mutable_data_pointer(mut self)
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

    pub fn split_first(): (read T from self, read [T] from self)? {
        if self.len() == 0usize { return none }
        present((read self[0usize], unsafe { sub<T>(read self, 1usize, self.len()) }))
    }
    pub fn split_last(): (read T from self, read [T] from self)? {
        let n = self.len()
        if n == 0usize { return none }
        present((read self[n - 1usize], unsafe { sub<T>(read self, 0usize, n - 1usize) }))
    }
    pub mut fn split_first_mut(): (mut T from self, mut [T] from self)? {
        let n = self.len()
        if n == 0usize { return none }
        let base = mutable_data_pointer(mut self)
        let tail = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base.add(1usize), n - 1usize)) }
        present((unsafe { mut *base }, unsafe { mut *tail }))
    }
    pub mut fn split_last_mut(): (mut T from self, mut [T] from self)? {
        let n = self.len()
        if n == 0usize { return none }
        let base = mutable_data_pointer(mut self)
        let last = unsafe { base.add(n - 1usize) }
        let head = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base, n - 1usize)) }
        present((unsafe { mut *last }, unsafe { mut *head }))
    }

    pub fn as_array<const N: usize>(): (read [T; N] from self)? {
        if self.len() != N { return none }
        // Safety: the length check covers exactly N initialized elements.
        present(unsafe { array_at<T, N>(read self, 0usize) })
    }
    pub mut fn as_mut_array<const N: usize>(): (mut [T; N] from self)? {
        if self.len() != N { return none }
        let base = mutable_data_pointer(mut self)
        // Safety: the length check covers exactly N initialized elements.
        present(unsafe { mut *base.cast<[T; N]>() })
    }
    pub fn as_chunks<const N: usize>(): (read [[T; N]] from self, read [T] from self) {
        if N == 0usize { super.panic.panic("chunk size must be nonzero") }
        let count = self.len() / N
        let head = count * N
        (
            unsafe { array_chunks_at<T, N>(read self, 0usize, count) },
            unsafe { sub<T>(read self, head, self.len()) }
        )
    }
    pub fn as_rchunks<const N: usize>(): (read [T] from self, read [[T; N]] from self) {
        if N == 0usize { super.panic.panic("chunk size must be nonzero") }
        let count = self.len() / N
        let start = self.len() - count * N
        (
            unsafe { sub<T>(read self, 0usize, start) },
            unsafe { array_chunks_at<T, N>(read self, start, count) }
        )
    }
    // Safety: `N != 0` and `N` divides the slice length.
    pub unsafe fn as_chunks_unchecked<const N: usize>(): read [[T; N]] from self {
        unsafe { array_chunks_at<T, N>(read self, 0usize, self.len() / N) }
    }
    // Safety: `N != 0` and `N` divides the slice length.
    pub mut unsafe fn as_chunks_unchecked_mut<const N: usize>(): mut [[T; N]] from self {
        let count = self.len() / N
        let base = mutable_data_pointer(mut self)
        let chunks = unsafe {
            core.mem.transmute<ptr<mut [[T; N]]>>(RawMut(base.cast<[T; N]>(), count))
        }
        unsafe { mut *chunks }
    }
    pub mut fn as_chunks_mut<const N: usize>(): (mut [[T; N]] from self, mut [T] from self) {
        if N == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        let count = n / N
        let head = count * N
        let base = mutable_data_pointer(mut self)
        // The chunk view and remainder are disjoint parts of the exclusive slice.
        let chunks = unsafe {
            core.mem.transmute<ptr<mut [[T; N]]>>(RawMut(base.cast<[T; N]>(), count))
        }
        let rest = unsafe {
            core.mem.transmute<ptr<mut [T]>>(RawMut(base.add(head), n - head))
        }
        (unsafe { mut *chunks }, unsafe { mut *rest })
    }
    pub mut fn as_rchunks_mut<const N: usize>(): (mut [T] from self, mut [[T; N]] from self) {
        if N == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        let count = n / N
        let start = n - count * N
        let base = mutable_data_pointer(mut self)
        // The remainder and chunk view are disjoint parts of the exclusive slice.
        let rest = unsafe {
            core.mem.transmute<ptr<mut [T]>>(RawMut(base, start))
        }
        let chunks = unsafe {
            core.mem.transmute<ptr<mut [[T; N]]>>(
                RawMut(base.add(start).cast<[T; N]>(), count)
            )
        }
        (unsafe { mut *rest }, unsafe { mut *chunks })
    }
    pub fn split_off_first(): (read T from self, read [T] from self)? { self.split_first() }
    pub fn split_off_last(): (read T from self, read [T] from self)? { self.split_last() }
    pub mut fn split_off_first_mut(): (mut T from self, mut [T] from self)? {
        self.split_first_mut()
    }
    pub mut fn split_off_last_mut(): (mut T from self, mut [T] from self)? {
        self.split_last_mut()
    }

    pub mut fn rotate_left(mid: usize): Unit {
        let n = self.len()
        if mid > n { super.panic.panic("rotation index out of bounds") }
        if mid == 0usize || mid == n { return () }
        var left = 0usize
        var right = mid
        while left + 1usize < right {
            right -= 1usize
            self.swap(left, right)
            left += 1usize
        }
        left = mid
        right = n
        while left + 1usize < right {
            right -= 1usize
            self.swap(left, right)
            left += 1usize
        }
        left = 0usize
        right = n
        while left + 1usize < right {
            right -= 1usize
            self.swap(left, right)
            left += 1usize
        }
    }
    pub mut fn rotate_right(mid: usize): Unit {
        let n = self.len()
        if mid > n { super.panic.panic("rotation index out of bounds") }
        if mid == 0usize || mid == n { return () }
        self.rotate_left(n - mid)
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
    pub mut fn copy_within(start: usize, end: usize, destination: usize): Unit {
        let n = self.len()
        if start > end || end > n { super.panic.panic("copy range out of bounds") }
        let count = end - start
        if destination > n || count > n - destination {
            super.panic.panic("copy destination out of bounds")
        }
        if destination < start {
            var i = 0usize
            while i < count {
                self[destination + i] = self[start + i]
                i += 1usize
            }
        } else {
            var i = count
            while i > 0usize {
                i -= 1usize
                self[destination + i] = self[start + i]
            }
        }
    }
}

extend<T> [T] {
    pub mut fn fill_with<F: fn(): T>(generate: take F): Unit {
        var i = 0usize
        while i < self.len() {
            self[i] = generate()
            i += 1usize
        }
    }
    pub mut fn swap_with_slice(other: mut [T]): Unit {
        if other.len() != self.len() { super.panic.panic("swap_with_slice length mismatch") }
        let left = mutable_data_pointer(mut self)
        let right = mutable_data_pointer(mut other)
        var i = 0usize
        while i < self.len() {
            unsafe { core.ptr.swap(left.add(i), right.add(i)) }
            i += 1usize
        }
    }
}

extend<T: Clone> [T] {
    pub mut fn clone_from_slice(source: read [T]): Unit {
        if source.len() != self.len() { super.panic.panic("clone_from_slice length mismatch") }
        var i = 0usize
        while i < source.len() {
            self[i] = source[i].clone()
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
    pub fn chunks(size: usize): SliceChunks<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        SliceChunks(read self, size, 0usize, self.len())
    }
    pub fn chunks_exact(size: usize): SliceChunksExact<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        let remainder = n % size
        let back = n - remainder
        SliceChunksExact(read self, size, 0usize, back, back)
    }
    pub fn rchunks(size: usize): SliceRChunks<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        SliceRChunks(read self, size, 0usize, self.len())
    }
    pub fn rchunks_exact(size: usize): SliceRChunksExact<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        let remainder = n % size
        SliceRChunksExact(read self, size, remainder, n, remainder)
    }
    pub fn windows(size: usize): SliceWindows<region self, T> {
        if size == 0usize { super.panic.panic("window size must be nonzero") }
        let n = self.len()
        let count = if size > n { 0usize } else { n - size + 1usize }
        SliceWindows(read self, size, 0usize, count)
    }
    pub fn array_windows<const N: usize>(): ArrayWindows<region self, T, N> {
        if N == 0usize { super.panic.panic("window size must be nonzero") }
        let n = self.len()
        let count = if N > n { 0usize } else { n - N + 1usize }
        ArrayWindows(read self, 0usize, count)
    }
}

pub type SliceChunks<region r, T> {
    items: read [T] from r
    size: usize
    front: usize
    back: usize
}
extend<region r, T> SliceChunks<region r, T> implements Iterator {
    type Item = read [T] from r
    mut fn next(): (read [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        let count = if self.back - start < self.size { self.back - start } else { self.size }
        self.front += count
        present(unsafe { sub<T>(self.items, start, start + count) })
    }
}
extend<region r, T> SliceChunks<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (read [T] from r)? {
        if self.front == self.back { return none }
        let remaining = self.back - self.front
        let remainder = remaining % self.size
        let count = if remainder == 0usize { self.size } else { remainder }
        let start = self.back - count
        self.back = start
        present(unsafe { sub<T>(self.items, start, start + count) })
    }
}

pub type SliceWindows<region r, T> {
    items: read [T] from r
    size: usize
    front: usize
    back: usize
}
extend<region r, T> SliceWindows<region r, T> implements Iterator {
    type Item = read [T] from r
    mut fn next(): (read [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        self.front += 1usize
        present(unsafe { sub<T>(self.items, start, start + self.size) })
    }
}

pub type ArrayWindows<region r, T, const N: usize> {
    items: read [T] from r
    front: usize
    back: usize
}
extend<region r, T, const N: usize> ArrayWindows<region r, T, N> implements Iterator {
    type Item = read [T; N] from r
    mut fn next(): (read [T; N] from r)? {
        if self.front == self.back { return none }
        let index = self.front
        self.front += 1usize
        // Safety: each index is a window start, so index + N stays inside the slice.
        present(unsafe { array_at<T, N>(self.items, index) })
    }
}
extend<region r, T, const N: usize> ArrayWindows<region r, T, N> implements BidirectionalIterator {
    mut fn next_back(): (read [T; N] from r)? {
        if self.front == self.back { return none }
        self.back -= 1usize
        // Safety: each index is a window start, so index + N stays inside the slice.
        present(unsafe { array_at<T, N>(self.items, self.back) })
    }
}

pub type SliceChunksMut<region r, T> {
    items: mut [T] from r
    size: usize
    front: usize
    back: usize
}
extend<region r, T> SliceChunksMut<region r, T> implements Iterator {
    type Item = mut [T] from r
    mut fn next(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        let count = if self.back - start < self.size { self.back - start } else { self.size }
        self.front += count
        present(unsafe { sub_mut<T>(mut *self.items, start, start + count) })
    }
}
extend<region r, T> SliceChunksMut<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let remaining = self.back - self.front
        let remainder = remaining % self.size
        let count = if remainder == 0usize { self.size } else { remainder }
        let start = self.back - count
        self.back = start
        present(unsafe { sub_mut<T>(mut *self.items, start, start + count) })
    }
}

extend<T> [T] {
    pub mut fn chunks_mut(size: usize): SliceChunksMut<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        SliceChunksMut(mut self, size, 0usize, n)
    }
    pub mut fn chunks_exact_mut(size: usize): SliceChunksExactMut<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        let remainder = n % size
        let back = n - remainder
        SliceChunksExactMut(mut self, size, 0usize, back, back)
    }
    pub mut fn rchunks_mut(size: usize): SliceRChunksMut<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        SliceRChunksMut(mut self, size, 0usize, n)
    }
    pub mut fn rchunks_exact_mut(size: usize): SliceRChunksExactMut<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        let remainder = n % size
        SliceRChunksExactMut(mut self, size, remainder, n, remainder)
    }
}

extend<T> [T] {
    pub mut fn first_chunk_mut<const N: usize>(): (mut [T; N] from self)? {
        if N > self.len() { return none }
        let base = mutable_data_pointer(mut self)
        // Safety: the checked array is in-bounds and the receiver is exclusive.
        present(unsafe { mut *base.cast<[T; N]>() })
    }

    pub mut fn last_chunk_mut<const N: usize>(): (mut [T; N] from self)? {
        if N > self.len() { return none }
        let base = mutable_data_pointer(mut self)
        // Safety: the checked suffix is in-bounds and the receiver is exclusive.
        present(unsafe { mut *base.add(self.len() - N).cast<[T; N]>() })
    }

    pub mut fn split_first_chunk_mut<const N: usize>(): ((mut [T; N] from self), (mut [T] from self))? {
        if N > self.len() { return none }
        let n = self.len()
        let base = mutable_data_pointer(mut self)
        let first = base.cast<[T; N]>()
        let rest = unsafe {
            core.mem.transmute<ptr<mut [T]>>(RawMut(base.add(N), n - N))
        }
        // Safety: these two checked ranges are disjoint parts of the exclusive slice.
        present((unsafe { mut *first }, unsafe { mut *rest }))
    }

    pub mut fn split_last_chunk_mut<const N: usize>(): ((mut [T] from self), (mut [T; N] from self))? {
        if N > self.len() { return none }
        let n = self.len()
        let start = n - N
        let base = mutable_data_pointer(mut self)
        let rest = unsafe {
            core.mem.transmute<ptr<mut [T]>>(RawMut(base, start))
        }
        let last = unsafe { base.add(start).cast<[T; N]>() }
        // Safety: these two checked ranges are disjoint parts of the exclusive slice.
        present((unsafe { mut *rest }, unsafe { mut *last }))
    }
}

extend<T> [T] {
    pub fn split<F: fn(read T): bool>(test: take F): SliceSplit<region self, T, F> {
        SliceSplit(read self, test, 0usize, self.len(), 0xffffffffffffffffusize, false, false, false, false)
    }
    pub fn splitn<F: fn(read T): bool>(count: usize, test: take F): SliceSplit<region self, T, F> {
        SliceSplit(read self, test, 0usize, self.len(), count, false, false, false, false)
    }
    pub fn rsplitn<F: fn(read T): bool>(count: usize, test: take F): SliceSplit<region self, T, F> {
        SliceSplit(read self, test, 0usize, self.len(), count, true, false, false, false)
    }
    pub fn split_inclusive<F: fn(read T): bool>(
        test: take F
    ): SliceSplit<region self, T, F> {
        SliceSplit(read self, test, 0usize, self.len(), 0xffffffffffffffffusize, false, true, false, false)
    }
    pub mut fn split_mut<F: fn(read T): bool>(
        test: take F
    ): SliceSplitMut<region self, T, F> {
        let n = self.len()
        SliceSplitMut(mut self, test, 0usize, n, false, false, false, 0xffffffffffffffffusize, false)
    }
    pub mut fn rsplit_mut<F: fn(read T): bool>(
        test: take F
    ): SliceSplitMut<region self, T, F> {
        let n = self.len()
        SliceSplitMut(mut self, test, 0usize, n, false, false, false, 0xffffffffffffffffusize, true)
    }
    pub mut fn splitn_mut<F: fn(read T): bool>(
        count: usize, test: take F
    ): SliceSplitMut<region self, T, F> {
        let n = self.len()
        SliceSplitMut(mut self, test, 0usize, n, false, false, false, count, false)
    }
    pub mut fn rsplitn_mut<F: fn(read T): bool>(
        count: usize, test: take F
    ): SliceSplitMut<region self, T, F> {
        let n = self.len()
        SliceSplitMut(mut self, test, 0usize, n, false, false, false, count, true)
    }
    pub mut fn split_inclusive_mut<F: fn(read T): bool>(
        test: take F
    ): SliceSplitMut<region self, T, F> {
        let n = self.len()
        SliceSplitMut(mut self, test, 0usize, n, true, false, false, 0xffffffffffffffffusize, false)
    }
    pub fn chunk_by<F: fn(read T, read T): bool>(
        same: take F
    ): SliceChunkBy<region self, T, F> {
        SliceChunkBy(read self, same, 0usize, self.len())
    }
    pub mut fn chunk_by_mut<F: fn(read T, read T): bool>(
        same: take F
    ): SliceChunkByMut<region self, T, F> {
        let n = self.len()
        SliceChunkByMut(mut self, same, 0usize, n)
    }
}

pub type SliceChunksExact<region r, T> {
    items: read [T] from r
    size: usize
    front: usize
    back: usize
    remainder_start: usize
}
extend<region r, T> SliceChunksExact<region r, T> implements Iterator {
    type Item = read [T] from r
    mut fn next(): (read [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        self.front += self.size
        present(unsafe { sub<T>(self.items, start, self.front) })
    }
}
extend<region r, T> SliceChunksExact<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (read [T] from r)? {
        if self.front == self.back { return none }
        self.back -= self.size
        present(unsafe { sub<T>(self.items, self.back, self.back + self.size) })
    }
}
extend<region r, T> SliceChunksExact<region r, T> {
    pub fn remainder(): read [T] from r {
        unsafe { sub<T>(self.items, self.remainder_start, self.items.len()) }
    }
}

pub type SliceRChunks<region r, T> {
    items: read [T] from r
    size: usize
    front: usize
    back: usize
}
extend<region r, T> SliceRChunks<region r, T> implements Iterator {
    type Item = read [T] from r
    mut fn next(): (read [T] from r)? {
        if self.front == self.back { return none }
        let count = if self.back - self.front < self.size { self.back - self.front } else { self.size }
        self.back -= count
        present(unsafe { sub<T>(self.items, self.back, self.back + count) })
    }
}
extend<region r, T> SliceRChunks<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (read [T] from r)? {
        if self.front == self.back { return none }
        let remaining = self.back - self.front
        let remainder = remaining % self.size
        let count = if remainder == 0usize { self.size } else { remainder }
        let start = self.front
        self.front += count
        present(unsafe { sub<T>(self.items, start, self.front) })
    }
}

pub type SliceRChunksExact<region r, T> {
    items: read [T] from r
    size: usize
    front: usize
    back: usize
    remainder_end: usize
}
extend<region r, T> SliceRChunksExact<region r, T> implements Iterator {
    type Item = read [T] from r
    mut fn next(): (read [T] from r)? {
        if self.front == self.back { return none }
        self.back -= self.size
        present(unsafe { sub<T>(self.items, self.back, self.back + self.size) })
    }
}
extend<region r, T> SliceRChunksExact<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (read [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        self.front += self.size
        present(unsafe { sub<T>(self.items, start, self.front) })
    }
}
extend<region r, T> SliceRChunksExact<region r, T> {
    pub fn remainder(): read [T] from r {
        unsafe { sub<T>(self.items, 0usize, self.remainder_end) }
    }
}

pub type SliceChunksExactMut<region r, T> {
    items: mut [T] from r
    size: usize
    front: usize
    back: usize
    remainder_start: usize
}
extend<region r, T> SliceChunksExactMut<region r, T> implements Iterator {
    type Item = mut [T] from r
    mut fn next(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        self.front += self.size
        present(unsafe { sub_mut<T>(mut *self.items, start, self.front) })
    }
}
extend<region r, T> SliceChunksExactMut<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (mut [T] from r)? {
        if self.front == self.back { return none }
        self.back -= self.size
        present(unsafe { sub_mut<T>(mut *self.items, self.back, self.back + self.size) })
    }
}
extend<region r, T> SliceChunksExactMut<region r, T> {
    pub mut fn remainder(): mut [T] from r {
        let n = self.items.len()
        unsafe { sub_mut<T>(mut *self.items, self.remainder_start, n) }
    }
}

pub type SliceRChunksMut<region r, T> {
    items: mut [T] from r
    size: usize
    front: usize
    back: usize
}
extend<region r, T> SliceRChunksMut<region r, T> implements Iterator {
    type Item = mut [T] from r
    mut fn next(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let count = if self.back - self.front < self.size { self.back - self.front } else { self.size }
        self.back -= count
        present(unsafe { sub_mut<T>(mut *self.items, self.back, self.back + count) })
    }
}
extend<region r, T> SliceRChunksMut<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let remaining = self.back - self.front
        let remainder = remaining % self.size
        let count = if remainder == 0usize { self.size } else { remainder }
        let start = self.front
        self.front += count
        present(unsafe { sub_mut<T>(mut *self.items, start, self.front) })
    }
}

pub type SliceRChunksExactMut<region r, T> {
    items: mut [T] from r
    size: usize
    front: usize
    back: usize
    remainder_end: usize
}
extend<region r, T> SliceRChunksExactMut<region r, T> implements Iterator {
    type Item = mut [T] from r
    mut fn next(): (mut [T] from r)? {
        if self.front == self.back { return none }
        self.back -= self.size
        present(unsafe { sub_mut<T>(mut *self.items, self.back, self.back + self.size) })
    }
}
extend<region r, T> SliceRChunksExactMut<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        self.front += self.size
        present(unsafe { sub_mut<T>(mut *self.items, start, self.front) })
    }
}
extend<region r, T> SliceRChunksExactMut<region r, T> {
    pub mut fn remainder(): mut [T] from r {
        unsafe { sub_mut<T>(mut *self.items, 0usize, self.remainder_end) }
    }
}

pub type SliceSplit<region r, T, F> {
    items: read [T] from r
    test: F
    front: usize
    back: usize
    remaining: usize
    from_back: bool
    inclusive: bool
    suppress_empty_tail: bool
    done: bool
}
extend<region r, T, F: fn(read T): bool> SliceSplit<region r, T, F> implements Iterator {
    type Item = read [T] from r
    mut fn next(): (read [T] from r)? {
        if self.done || self.remaining == 0usize { return none }
        self.remaining -= 1usize
        if self.front == self.back {
            if self.inclusive && self.suppress_empty_tail {
                self.done = true
                return none
            }
            self.done = true
            return present(unsafe { sub<T>(self.items, self.front, self.back) })
        }
        if self.remaining == 0usize {
            self.done = true
            return present(unsafe { sub<T>(self.items, self.front, self.back) })
        }
        if self.from_back {
            var i = self.back
            while i > self.front {
                i -= 1usize
                if self.test(read self.items[i]) {
                    let start = i + 1usize
                    let part = unsafe { sub<T>(self.items, start, self.back) }
                    self.back = i
                    return present(part)
                }
            }
            self.done = true
            return present(unsafe { sub<T>(self.items, self.front, self.back) })
        }
        var i = self.front
        while i < self.back {
            if self.test(read self.items[i]) {
                let end = if self.inclusive { i + 1usize } else { i }
                let part = unsafe { sub<T>(self.items, self.front, end) }
                self.front = i + 1usize
                if self.inclusive && self.front == self.back {
                    self.suppress_empty_tail = true
                }
                return present(part)
            }
            i += 1usize
        }
        self.done = true
        present(unsafe { sub<T>(self.items, self.front, self.back) })
    }
}
extend<region r, T, F: fn(read T): bool> SliceSplit<region r, T, F> implements BidirectionalIterator {
    mut fn next_back(): (read [T] from r)? {
        if self.done || self.remaining == 0usize { return none }
        self.remaining -= 1usize
        if self.front == self.back {
            if self.inclusive && self.suppress_empty_tail {
                self.done = true
                return none
            }
            self.done = true
            return present(unsafe { sub<T>(self.items, self.front, self.back) })
        }
        if self.remaining == 0usize {
            self.done = true
            return present(unsafe { sub<T>(self.items, self.front, self.back) })
        }
        var i = self.back
        while i > self.front {
            i -= 1usize
            if self.test(read self.items[i]) {
                if self.inclusive {
                    if i + 1usize == self.back { continue }
                    let start = i + 1usize
                    let part = unsafe { sub<T>(self.items, start, self.back) }
                    self.back = start
                    return present(part)
                }
                let start = i + 1usize
                let part = unsafe { sub<T>(self.items, start, self.back) }
                self.back = i
                return present(part)
            }
        }
        self.done = true
        present(unsafe { sub<T>(self.items, self.front, self.back) })
    }
}

pub type SliceSplitMut<region r, T, F> {
    items: mut [T] from r
    test: F
    front: usize
    back: usize
    inclusive: bool
    suppress_empty_tail: bool
    done: bool
    remaining: usize
    from_back: bool
}
extend<region r, T, F: fn(read T): bool> SliceSplitMut<region r, T, F> implements Iterator {
    type Item = mut [T] from r
    mut fn next(): (mut [T] from r)? {
        if self.done || self.remaining == 0usize { return none }
        self.remaining -= 1usize
        if self.front == self.back {
            if self.inclusive && self.suppress_empty_tail {
                self.done = true
                return none
            }
            self.done = true
            return present(unsafe { sub_mut<T>(mut *self.items, self.front, self.back) })
        }
        if self.remaining == 0usize {
            self.done = true
            return present(unsafe { sub_mut<T>(mut *self.items, self.front, self.back) })
        }
        if self.from_back {
            var i = self.back
            while i > self.front {
                i -= 1usize
                let matches = self.test(unsafe {
                    read *mutable_data_pointer(mut *self.items).add(i)
                })
                if matches {
                    let start = i + 1usize
                    let part = unsafe { sub_mut<T>(mut *self.items, start, self.back) }
                    self.back = i
                    return present(part)
                }
            }
            self.done = true
            return present(unsafe { sub_mut<T>(mut *self.items, self.front, self.back) })
        }
        var i = self.front
        while i < self.back {
            if self.test(unsafe { read *mutable_data_pointer(mut *self.items).add(i) }) {
                let end = if self.inclusive { i + 1usize } else { i }
                let part = unsafe { sub_mut<T>(mut *self.items, self.front, end) }
                self.front = i + 1usize
                if self.inclusive && self.front == self.back {
                    self.suppress_empty_tail = true
                }
                return present(part)
            }
            i += 1usize
        }
        self.done = true
        present(unsafe { sub_mut<T>(mut *self.items, self.front, self.back) })
    }
}

pub type SliceChunkBy<region r, T, F> {
    items: read [T] from r
    same: F
    front: usize
    back: usize
}
extend<region r, T, F: fn(read T, read T): bool> SliceChunkBy<region r, T, F> implements Iterator {
    type Item = read [T] from r
    mut fn next(): (read [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        var end = start + 1usize
        while end < self.back && self.same(read self.items[end - 1usize], read self.items[end]) {
            end += 1usize
        }
        self.front = end
        present(unsafe { sub<T>(self.items, start, end) })
    }
}
extend<region r, T, F: fn(read T, read T): bool> SliceChunkBy<region r, T, F> implements BidirectionalIterator {
    mut fn next_back(): (read [T] from r)? {
        if self.front == self.back { return none }
        let end = self.back
        var start = end - 1usize
        while start > self.front && self.same(read self.items[start - 1usize], read self.items[start]) {
            start -= 1usize
        }
        self.back = start
        present(unsafe { sub<T>(self.items, start, end) })
    }
}

pub type SliceChunkByMut<region r, T, F> {
    items: mut [T] from r
    same: F
    front: usize
    back: usize
}
extend<region r, T, F: fn(read T, read T): bool> SliceChunkByMut<region r, T, F> implements Iterator {
    type Item = mut [T] from r
    mut fn next(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        var end = start + 1usize
        let base = mutable_data_pointer(mut *self.items)
        while end < self.back && self.same(
            unsafe { read *base.add(end - 1usize) },
            unsafe { read *base.add(end) }
        ) {
            end += 1usize
        }
        self.front = end
        present(unsafe { sub_mut<T>(mut *self.items, start, end) })
    }
}
extend<region r, T, F: fn(read T, read T): bool> SliceChunkByMut<region r, T, F> implements BidirectionalIterator {
    mut fn next_back(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let end = self.back
        let base = mutable_data_pointer(mut *self.items)
        var start = end - 1usize
        while start > self.front && self.same(
            unsafe { read *base.add(start - 1usize) },
            unsafe { read *base.add(start) }
        ) {
            start -= 1usize
        }
        self.back = start
        present(unsafe { sub_mut<T>(mut *self.items, start, end) })
    }
}

extend<region r, T> SliceIterMut<region r, T> {
    pub fn into_slice(receiver self: take Self): mut [T] from r {
        unsafe { sub_mut<T>(mut *self.items, self.front, self.back) }
    }
}

extend<T, const N: usize> [[T; N]] {
    pub fn as_flattened(): read [T] from self {
        let total = match self.len().checked_mul(N) {
            present(value) => value,
            none => super.panic.panic("flattened length overflows")
        }
        let fat = core.ptr.from_ref(self)
        let raw = unsafe { core.mem.transmute<RawRead<[T; N]>>(fat) }
        // Safety: the arrays are packed, so the element pointer covers `total` values.
        let part = unsafe {
            core.mem.transmute<ptr<read [T]>>(RawRead(raw.data.cast<T>(), total))
        }
        unsafe { read *part }
    }
    pub mut fn as_flattened_mut(): mut [T] from self {
        let total = match self.len().checked_mul(N) {
            present(value) => value,
            none => super.panic.panic("flattened length overflows")
        }
        let base = mutable_data_pointer(mut self)
        // Safety: the arrays are packed, so the element pointer covers `total` values.
        let part = unsafe {
            core.mem.transmute<ptr<mut [T]>>(RawMut(base.cast<T>(), total))
        }
        unsafe { mut *part }
    }
}

extend<T, const N: usize> [T; N] {
    pub fn each_ref<region r>(
        receiver self: read Self from r
    ): [read T from r; N] from r {
        var result = core.mem.MaybeUninit<[read T from r; N]>.uninit()
        let slots = core.ptr.from_mut(result).cast<core.mem.MaybeUninit<read T from r>>()
        let base = core.ptr.from_ref(self).cast<T>()
        var i = 0usize
        // Safety: every slot and every source element is in bounds.
        while i < N {
            unsafe { mut *slots.add(i) }.write(unsafe { read *base.add(i) })
            i += 1usize
        }
        // Safety: every element of the result array was initialized above.
        unsafe { result.assume_init() }
    }

    pub fn each_mut<region r>(
        receiver self: mut Self from r
    ): [mut T from r; N] from r {
        var result = core.mem.MaybeUninit<[mut T from r; N]>.uninit()
        let slots = core.ptr.from_mut(result).cast<core.mem.MaybeUninit<mut T from r>>()
        let base = core.ptr.from_mut(self).cast<T>()
        var i = 0usize
        // Safety: every slot and source element is in bounds; distinct indices
        // create disjoint mutable views that remain within the source array.
        while i < N {
            unsafe { mut *slots.add(i) }.write(unsafe { mut *base.add(i) })
            i += 1usize
        }
        // Safety: every element of the result array was initialized above.
        unsafe { result.assume_init() }
    }
}
