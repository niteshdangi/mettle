import super.cmp.{PartialEq, PartialOrd}
import super.iter.Iterator

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

// Safety: `index < xs.len()`.
unsafe fn element<T>(xs: mut [T], index: usize): ptr<mut T> {
    let fat = core.ptr.from_mut(xs)
    let raw = unsafe { core.mem.transmute<RawMut<T>>(fat) }
    raw.data.add(index)
}

extend<T> [T] {
    pub fn is_empty(): bool { self.len() == 0usize }
    pub fn get(index: usize): (read T from self)? {
        if index < self.len() { present(read self[index]) } else { none }
    }
    pub fn first(): (read T from self)? { self.get(0usize) }
    pub fn last(): (read T from self)? {
        if self.len() == 0usize { none } else { self.get(self.len() - 1usize) }
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

extend<T: PartialOrd> [T] {
    // Err carries the insertion point; the slice must be sorted ascending.
    pub fn binary_search(value: read T): usize throws usize {
        var low = 0usize
        var high = self.len()
        while low < high {
            let mid = low + (high - low) / 2usize
            if self[mid] < value {
                low = mid + 1usize
            } else {
                if self[mid] > value { high = mid } else { return mid }
            }
        }
        throw low
    }
    pub fn is_sorted(): bool {
        var i = 1usize
        while i < self.len() {
            if self[i] < self[i - 1usize] { return false }
            i += 1usize
        }
        true
    }
    // In-place heapsort: O(n log n) worst case, no allocation, NOT stable.
    pub mut fn sort() {
        let n = self.len()
        if n < 2usize { return }
        var start = n / 2usize
        while start > 0usize {
            start -= 1usize
            sift_down<T>(mut self, start, n)
        }
        var end = n
        while end > 1usize {
            end -= 1usize
            self.swap(0usize, end)
            sift_down<T>(mut self, 0usize, end)
        }
    }
}

fn sift_down<T: PartialOrd>(xs: mut [T], start: usize, end: usize) {
    var root = start
    while true {
        var child = root * 2usize + 1usize
        if child >= end { return }
        if child + 1usize < end && xs[child] < xs[child + 1usize] { child += 1usize }
        if xs[root] < xs[child] {
            xs.swap(root, child)
            root = child
        } else {
            return
        }
    }
}

// Borrowing iteration over the elements of a slice.
pub type SliceIter<region r, T> { items: read [T] from r; index: usize }
extend<region r, T> SliceIter<region r, T> implements Iterator {
    type Item = read T from r
    mut fn next(): (read T from r)? {
        if self.index < self.items.len() {
            let i = self.index
            self.index += 1usize
            present(read self.items[i])
        } else {
            none
        }
    }
}

pub type SliceIterMut<region r, T> { items: mut [T] from r; index: usize }
extend<region r, T> SliceIterMut<region r, T> implements Iterator {
    type Item = mut T from r
    mut fn next(): (mut T from r)? {
        if self.index < self.items.len() {
            let i = self.index
            self.index += 1usize
            present(mut self.items[i])
        } else {
            none
        }
    }
}

extend<T> [T] {
    pub fn iter(): SliceIter<region self, T> { SliceIter(read self, 0usize) }
    pub mut fn iter_mut(): SliceIterMut<region self, T> { SliceIterMut(mut self, 0usize) }
}

// Copy-valued iteration over the bytes of a slice: yields `u8` while holding a
// read loan on the slice; allocates nothing.
pub type SliceBytes<region r> { items: read [u8] from r; index: usize }
extend<region r> SliceBytes<region r> implements Iterator {
    type Item = u8
    mut fn next(): u8? {
        if self.index < self.items.len() {
            let value = self.items[self.index]
            self.index += 1usize
            present(value)
        } else {
            none
        }
    }
}

extend [u8] {
    pub fn bytes(): SliceBytes<region self> { SliceBytes(read self, 0usize) }
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
    pub mut fn split_at_mut(mid: usize): (mut [T] from self, mut [T] from self) {
        if mid > self.len() { super.panic.panic("split index out of bounds") }
        let n = self.len()
        let base = unsafe { element<T>(mut self, 0usize) }
        let left = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base, mid)) }
        let right = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base.add(mid), n - mid)) }
        (unsafe { mut *left }, unsafe { mut *right })
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
        if size == 0usize || index + size > self.len() { return none }
        self.subslice(index, index + size)
    }
    // The `index`-th chunk of `size` elements; the last chunk may be shorter.
    pub fn chunk(index: usize, size: usize): (read [T] from self)? {
        if size == 0usize { return none }
        let start = index * size
        if start >= self.len() { return none }
        let end = if self.len() - start < size { self.len() } else { start + size }
        self.subslice(start, end)
    }
}
