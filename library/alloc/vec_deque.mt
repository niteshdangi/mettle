import package.core.iter.{Iterator, BidirectionalIterator, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems}
import package.core.clone.Clone
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.hash.{Hash, Hasher}
import package.core.fmt

import super.alloc.{Allocator, Global, AllocError, PushError, layout_unchecked, handle_alloc_error, layout_of, dangling_for}

copy type RawSlice<T> { data: ptr<read T>; len: usize }

// Safety: `p` is aligned and valid for reads of `n` initialized elements.
unsafe fn slice_ptr<T>(p: ptr<mut T>, n: usize): ptr<read [T]> {
    unsafe { core.mem.transmute<ptr<read [T]>>(RawSlice(p.cast_const(), n)) }
}
// Safety: `p` is aligned and valid for exclusive access to `n` elements.
unsafe fn slice_ptr_mut<T>(p: ptr<mut T>, n: usize): ptr<mut [T]> {
    unsafe { core.mem.transmute<ptr<mut [T]>>(RawSlice(p.cast_const(), n)) }
}

// Growable ring buffer owning its block and allocator.
pub type Deque<T, A: Allocator = Global> {
    buf: ptr<mut T>
    cap: usize
    head: usize
    len: usize
    a: A
    drop {
        while self.len != 0usize {
            let v = self.pop_front()
        }
        if self.cap != 0usize && core.mem.size_of<T>() != 0usize {
            let layout = unsafe { layout_unchecked(self.cap * core.mem.size_of<T>(), core.mem.align_of<T>()) }
            unsafe { self.a.deallocate(self.buf.cast<u8>(), layout) }
        }
    }
}

pub fn new_in<T, A: Allocator>(a: take A): Deque<T, A> {
    let cap = if core.mem.size_of<T>() == 0usize { 0x7fffffffffffffffusize } else { 0usize }
    Deque(dangling_for<T>(), cap, 0usize, 0usize, a)
}
pub fn new<T>(): Deque<T> { new_in(Global()) }

extend<T, A: Allocator> Deque<T, A> {
    pub fn len(): usize { self.len }
    pub fn capacity(): usize { self.cap }
    pub fn is_empty(): bool { self.len == 0usize }
    pub fn allocator(): read A from self { read self.a }

    fn physical(i: usize): usize {
        let j = self.head + i
        if j >= self.cap { j - self.cap } else { j }
    }

    // Moves the elements to the front of a larger block; failure changes nothing.
    mut fn grow(): Unit throws AllocError {
        let size = core.mem.size_of<T>()
        if size == 0usize { return () }
        if self.cap > 0x7fffffffffffffffusize / 2usize {
            throw AllocError(0xffffffffffffffffusize, core.mem.align_of<T>())
        }
        let ncap = if self.cap == 0usize { 4usize } else { self.cap * 2usize }
        let align = core.mem.align_of<T>()
        let bytes = match ncap.checked_mul(size) {
            present(b) => b,
            none => throw AllocError(0xffffffffffffffffusize, align)
        }
        if bytes > 0x7fffffffffffffffusize - (align - 1usize) {
            throw AllocError(bytes, align)
        }
        let np = (try self.a.allocate(unsafe { layout_unchecked(bytes, align) })).cast<T>()
        var i = 0usize
        while i < self.len {
            unsafe { core.ptr.`copy`(self.buf.add(self.physical(i)).cast_const(), np.add(i), 1usize) }
            i += 1usize
        }
        if self.cap != 0usize {
            unsafe { self.a.deallocate(self.buf.cast<u8>(), layout_unchecked(self.cap * size, align)) }
        }
        self.buf = np
        self.cap = ncap
        self.head = 0usize
    }
    pub mut fn try_reserve(additional: usize): Unit throws AllocError {
        let need = match self.len.checked_add(additional) {
            present(n) => n,
            none => throw AllocError(0xffffffffffffffffusize, core.mem.align_of<T>())
        }
        while need > self.cap { try self.grow() }
    }
    pub mut fn try_reserve_one(): Unit throws AllocError {
        try self.try_reserve(1usize)
    }
    pub mut fn reserve(additional: usize): Unit {
        match capture self.try_reserve(additional) {
            success(_) => (),
            failure(_) => handle_alloc_error(layout_of<T>())
        }
    }
    pub mut fn try_reserve_exact(additional: usize): Unit throws AllocError {
        try self.try_reserve(additional)
    }
    pub mut fn reserve_exact(additional: usize): Unit {
        self.reserve(additional)
    }
    pub mut fn shrink_to_fit(): Unit { self.shrink_to(0usize) }
    pub mut fn shrink_to(min_capacity: usize): Unit {
        let size = core.mem.size_of<T>()
        let target = if min_capacity < self.len { self.len } else { min_capacity }
        if size == 0usize || self.cap <= target { return () }
        let align = core.mem.align_of<T>()
        if target == 0usize {
            if self.cap != 0usize {
                unsafe { self.a.deallocate(self.buf.cast<u8>(), layout_unchecked(self.cap * size, align)) }
            }
            self.buf = dangling_for<T>()
            self.cap = 0usize
            self.head = 0usize
            return ()
        }
        let bytes = match target.checked_mul(size) {
            present(n) => n,
            none => { return }
        }
        let layout = unsafe { layout_unchecked(bytes, align) }
        let new_buf = match capture self.a.allocate(layout) {
            success(p) => p.cast<T>(),
            failure(_) => { return () }
        }
        // Safety: each logical source slot is initialized, and the fresh
        // allocation has room for all `target` elements.
        var i = 0usize
        while i < self.len {
            unsafe {
                core.ptr.`copy`(self.buf.add(self.physical(i)).cast_const(),
                                new_buf.add(i), 1usize)
            }
            i += 1usize
        }
        if self.cap != 0usize {
            unsafe { self.a.deallocate(self.buf.cast<u8>(), layout_unchecked(self.cap * size, align)) }
        }
        self.buf = new_buf
        self.cap = target
        self.head = 0usize
    }
    pub mut fn try_push_back(value: take T): Unit throws PushError<T> {
        match capture self.try_reserve_one() {
            success(_) => {},
            failure(error) => { throw PushError(value, error) }
        }
        let at = self.physical(self.len)
        unsafe { core.ptr.write(self.buf.add(at), value) }
        self.len += 1usize
    }
    pub mut fn try_push_front(value: take T): Unit throws PushError<T> {
        match capture self.try_reserve_one() {
            success(_) => {},
            failure(error) => { throw PushError(value, error) }
        }
        self.head = if self.head == 0usize { self.cap - 1usize } else { self.head - 1usize }
        unsafe { core.ptr.write(self.buf.add(self.head), value) }
        self.len += 1usize
    }
    pub mut fn push_back(value: take T): Unit {
        match capture self.try_reserve_one() {
            success(_) => {},
            failure(_) => handle_alloc_error(layout_of<T>())
        }
        let at = self.physical(self.len)
        unsafe { core.ptr.write(self.buf.add(at), value) }
        self.len += 1usize
    }
    pub mut fn push_front(value: take T): Unit {
        match capture self.try_reserve_one() {
            success(_) => {},
            failure(_) => handle_alloc_error(layout_of<T>())
        }
        self.head = if self.head == 0usize { self.cap - 1usize } else { self.head - 1usize }
        unsafe { core.ptr.write(self.buf.add(self.head), value) }
        self.len += 1usize
    }
    pub mut fn pop_front(): T? {
        if self.len == 0usize { return none }
        let v = unsafe { core.ptr.`read`(self.buf.add(self.head)) }
        self.head = self.physical(1usize)
        self.len -= 1usize
        present(v)
    }
    pub mut fn pop_back(): T? {
        if self.len == 0usize { return none }
        self.len -= 1usize
        present(unsafe { core.ptr.`read`(self.buf.add(self.physical(self.len))) })
    }
    pub mut fn pop_front_if<F: fn(mut T): bool>(test: take F): T? {
        if self.len == 0usize { return none }
        let first = self.get_mut(0usize).unwrap()
        if test(first) { self.pop_front() } else { none }
    }
    pub mut fn pop_back_if<F: fn(mut T): bool>(test: take F): T? {
        if self.len == 0usize { return none }
        let last = self.get_mut(self.len - 1usize).unwrap()
        if test(last) { self.pop_back() } else { none }
    }
    pub fn get(i: usize): (read T from self)? {
        if i >= self.len { return none }
        present(unsafe { read *self.buf.add(self.physical(i)) })
    }
    pub mut fn get_mut(i: usize): (mut T from self)? {
        if i >= self.len { return none }
        present(unsafe { mut *self.buf.add(self.physical(i)) })
    }
    pub mut fn insert(i: usize, value: take T): Unit {
        if i > self.len { super.alloc.panic_precondition() }
        if i == 0usize { self.push_front(value); return () }
        if i == self.len { self.push_back(value); return () }
        self.reserve(1usize)
        var j = self.len
        while j > i {
            let from = self.physical(j - 1usize)
            let to = self.physical(j)
            unsafe {
                let moved = core.ptr.`read`(self.buf.add(from))
                core.ptr.write(self.buf.add(to), moved)
            }
            j -= 1usize
        }
        unsafe { core.ptr.write(self.buf.add(self.physical(i)), value) }
        self.len += 1usize
    }
    pub mut fn remove(i: usize): T {
        if i >= self.len { super.alloc.panic_precondition() }
        let value = unsafe { core.ptr.`read`(self.buf.add(self.physical(i))) }
        var j = i
        while j + 1usize < self.len {
            let from = self.physical(j + 1usize)
            let to = self.physical(j)
            unsafe {
                let moved = core.ptr.`read`(self.buf.add(from))
                core.ptr.write(self.buf.add(to), moved)
            }
            j += 1usize
        }
        self.len -= 1usize
        value
    }
    pub mut fn swap_remove_front(i: usize): T {
        if i >= self.len { super.alloc.panic_precondition() }
        if i != 0usize {
            unsafe { core.ptr.swap(self.buf.add(self.head), self.buf.add(self.physical(i))) }
        }
        self.pop_front().unwrap()
    }
    pub mut fn swap_remove_back(i: usize): T {
        if i >= self.len { super.alloc.panic_precondition() }
        let last = self.len - 1usize
        if i != last {
            unsafe { core.ptr.swap(self.buf.add(self.physical(i)), self.buf.add(self.physical(last))) }
        }
        self.pop_back().unwrap()
    }

    pub fn as_slices(): (read [T] from self, read [T] from self) {
        let first_len = if self.len < self.cap - self.head {
            self.len
        } else {
            self.cap - self.head
        }
        let second_len = self.len - first_len
        let first = unsafe { read *slice_ptr(self.buf.add(self.head), first_len) }
        let second = unsafe { read *slice_ptr(self.buf, second_len) }
        (first, second)
    }
    pub mut fn as_mut_slices(): (mut [T] from self, mut [T] from self) {
        let first_len = if self.len < self.cap - self.head {
            self.len
        } else {
            self.cap - self.head
        }
        let second_len = self.len - first_len
        let first_ptr = unsafe { self.buf.add(self.head) }
        let second_ptr = self.buf
        let first = unsafe { slice_ptr_mut(first_ptr, first_len) }
        let second = unsafe { slice_ptr_mut(second_ptr, second_len) }
        (unsafe { mut *first }, unsafe { mut *second })
    }
    pub mut fn rotate_left(mid: usize): Unit {
        if mid > self.len { super.alloc.panic_precondition() }
        var i = 0usize
        while i < mid {
            let value = self.pop_front().unwrap()
            self.push_back(value)
            i += 1usize
        }
    }
    pub mut fn rotate_right(mid: usize): Unit {
        if mid > self.len { super.alloc.panic_precondition() }
        var i = 0usize
        while i < mid {
            let value = self.pop_back().unwrap()
            self.push_front(value)
            i += 1usize
        }
    }
    pub mut fn make_contiguous(): mut [T] from self {
        let size = core.mem.size_of<T>()
        if size == 0usize {
            self.head = 0usize
            return unsafe { mut *slice_ptr_mut(self.buf, self.len) }
        }
        if self.len == 0usize {
            self.head = 0usize
            return unsafe { mut *slice_ptr_mut(self.buf, 0usize) }
        }
        if self.len <= self.cap - self.head {
            return unsafe {
                mut *slice_ptr_mut(self.buf.add(self.head), self.len)
            }
        }
        if self.head != 0usize {
            let align = core.mem.align_of<T>()
            let layout = unsafe { layout_unchecked(self.cap * size, align) }
            let new_buf = match capture self.a.allocate(layout) {
                success(p) => p.cast<T>(),
                failure(_) => handle_alloc_error(layout)
            }
            var i = 0usize
            while i < self.len {
                unsafe {
                    let value = core.ptr.`read`(self.buf.add(self.physical(i)))
                    core.ptr.write(new_buf.add(i), value)
                }
                i += 1usize
            }
            unsafe { self.a.deallocate(self.buf.cast<u8>(), layout) }
            self.buf = new_buf
            self.head = 0usize
        }
        unsafe { mut *slice_ptr_mut(self.buf, self.len) }
    }
    pub mut fn retain_mut(keep: fn(mut T): bool): Unit {
        let n = self.len
        let _ = self.make_contiguous()
        let base = unsafe { self.buf.add(self.head) }
        self.len = 0usize
        var read_at = 0usize
        var kept = 0usize
        while read_at < n {
            let p = unsafe { base.add(read_at) }
            let alive = keep(unsafe { mut *p })
            read_at += 1usize
            if alive {
                if kept != read_at - 1usize {
                    unsafe { core.ptr.`copy`(p.cast_const(), base.add(kept), 1usize) }
                }
                kept += 1usize
            } else {
                unsafe { core.ptr.drop_in_place(p) }
            }
        }
        self.len = kept
    }
    pub mut fn range_mut(start: usize, end: usize): DequeRangeMut<region self, T, A> {
        if start > end || end > self.len { super.alloc.panic_precondition() }
        DequeRangeMut(mut self, start, end)
    }
    pub mut fn split_off(at: usize): Deque<T, A> where A: Clone {
        if at > self.len { super.alloc.panic_precondition() }
        let count = self.len - at
        var other = new_in<T, A>(self.a.clone())
        other.reserve_exact(count)
        while self.len > at {
            other.push_front(self.pop_back().unwrap())
        }
        other
    }
    pub mut fn resize_with<F: fn(): T>(n: usize, generate: take F): Unit {
        if n < self.len {
            while self.len > n { let value = self.pop_back() }
            return ()
        }
        self.reserve(n - self.len)
        while self.len < n { self.push_back(generate()) }
    }
    pub fn front(): (read T from self)? { self.get(0usize) }
    pub mut fn front_mut(): (mut T from self)? { self.get_mut(0usize) }
    pub fn back(): (read T from self)? {
        if self.len == 0usize { none } else { self.get(self.len - 1usize) }
    }
    pub mut fn back_mut(): (mut T from self)? {
        if self.len == 0usize { none } else { self.get_mut(self.len - 1usize) }
    }
    pub mut fn clear(): Unit {
        while self.len != 0usize {
            let v = self.pop_front()
        }
    }
}

extend<T, A: Allocator> Deque<T, A> implements package.core.ops.Index<usize> {
    type Output = T
    fn index(i: read usize): read T from self {
        if i >= self.len { super.alloc.panic_precondition() }
        unsafe { read *self.buf.add(self.physical(i)) }
    }
}
extend<T, A: Allocator> Deque<T, A> implements package.core.ops.IndexMut<usize> {
    type Output = T
    mut fn index_mut(i: read usize): mut T from self {
        if i >= self.len { super.alloc.panic_precondition() }
        unsafe { mut *self.buf.add(self.physical(i)) }
    }
}

pub type DequeRangeMut<region r, T, A: Allocator> {
    deque: mut Deque<T, A> from r
    front: usize
    back: usize
}
extend<region r, T, A: Allocator> DequeRangeMut<region r, T, A> implements Iterator {
    type Item = mut T from r
    mut fn next(): (mut T from r)? {
        if self.front == self.back { return none }
        let index = self.front
        self.front += 1usize
        self.deque.get_mut(index)
    }
}
extend<region r, T, A: Allocator> DequeRangeMut<region r, T, A> implements BidirectionalIterator {
    mut fn next_back(): (mut T from r)? {
        if self.front == self.back { return none }
        self.back -= 1usize
        self.deque.get_mut(self.back)
    }
}


// Borrowed front-to-back iterator over a ring buffer.
pub type DequeIter<region r, T, A: Allocator> { deque: read Deque<T, A> from r; index: usize }
extend<region r, T, A: Allocator> DequeIter<region r, T, A> implements Iterator {
    type Item = read T from r
    mut fn next(): (read T from r)? {
        if self.index < self.deque.len {
            let i = self.index
            self.index += 1usize
            present(unsafe { read *self.deque.buf.add(self.deque.physical(i)) })
        } else {
            none
        }
    }
}
extend<T, A: Allocator> Deque<T, A> implements Iterable {
    type Item = T
    type Iter<region r> = DequeIter<region r, T, A>
    fn iter<region r>(receiver self: read Self from r): DequeIter<region r, T, A> { DequeIter(read self, 0usize) }
}

// Mutable front-to-back iterator over a ring buffer.
pub type DequeIterMut<region r, T, A: Allocator> { deque: mut Deque<T, A> from r; index: usize }
extend<region r, T, A: Allocator> DequeIterMut<region r, T, A> implements Iterator {
    type Item = mut T from r
    mut fn next(): (mut T from r)? {
        if self.index < self.deque.len {
            let i = self.index
            self.index += 1usize
            present(unsafe { mut *self.deque.buf.add(self.deque.physical(i)) })
        } else {
            none
        }
    }
}
extend<T, A: Allocator> Deque<T, A> implements MutableIterable {
    type Item = T
    type IterMut<region r> = DequeIterMut<region r, T, A>
    fn iter_mut<region r>(receiver self: mut Self from r): DequeIterMut<region r, T, A> { DequeIterMut(mut self, 0usize) }
}

pub type DequeIntoIter<T, A: Allocator = Global> { deque: Deque<T, A> }
extend<T, A: Allocator> DequeIntoIter<T, A> implements Iterator {
    type Item = T
    mut fn next(): T? { self.deque.pop_front() }
}
extend<T, A: Allocator> Deque<T, A> implements OwnedIterable {
    type Item = T
    type IntoIter = DequeIntoIter<T, A>
    fn into_iter(receiver self: take Self): DequeIntoIter<T, A> {
        DequeIntoIter(take self)
    }
}

extend<T: Clone, A: Allocator + Clone> Deque<T, A> implements Clone {
    fn clone(): Deque<T, A> {
        var out = new_in<T, A>(self.a.clone())
        var i = 0usize
        while i < self.len {
            out.push_back(self[i].clone())
            i += 1usize
        }
        out
    }
}
extend<T: PartialEq, A: Allocator> Deque<T, A> implements PartialEq {
    fn eq(other: read Deque<T, A>): bool {
        if self.len != other.len { return false }
        var i = 0usize
        while i < self.len {
            if !self[i].eq(other[i]) { return false }
            i += 1usize
        }
        true
    }
}
extend<T: Eq, A: Allocator> Deque<T, A> implements Eq {}
extend<T: PartialOrd, A: Allocator> Deque<T, A> implements PartialOrd {
    fn partial_cmp(other: read Deque<T, A>): Ordering? {
        var i = 0usize
        while i < self.len && i < other.len {
            match self[i].partial_cmp(other[i]) {
                present(o) => { if !o.is_eq() { return present(o) } },
                none => { return none }
            }
            i += 1usize
        }
        self.len.partial_cmp(other.len)
    }
}
extend<T: Ord, A: Allocator> Deque<T, A> implements Ord {
    fn cmp(other: read Deque<T, A>): Ordering {
        var i = 0usize
        while i < self.len && i < other.len {
            let o = self[i].cmp(other[i])
            if !o.is_eq() { return o }
            i += 1usize
        }
        self.len.cmp(other.len)
    }
}
// Hashes like the slice of the same elements, front to back.
extend<T: Hash, A: Allocator> Deque<T, A> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit {
        state.write_usize(self.len)
        var i = 0usize
        while i < self.len {
            self[i].hash(mut state)
            i += 1usize
        }
    }
}
extend<T: fmt.Debug, A: Allocator> Deque<T, A> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try f.debug_open("[")
        var i = 0usize
        while i < self.len {
            try f.debug_item_start(i == 0usize)
            try T.(fmt.Debug).fmt(self[i], mut f)
            try f.debug_item_end()
            i += 1usize
        }
        try f.debug_close("]", self.len == 0usize)
    }
}
extend<T, A: Allocator> Deque<T, A> implements ExtendItems<T> {
    mut fn extend<I: OwnedIterable<Item = T>>(items: take I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { self.push_back(item) }, none => { break } }
        }
    }
}
extend<T> Deque<T> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(items: take I): Deque<T> {
        var out = new<T>()
        out.extend(items)
        out
    }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<T: Transferable, A: Allocator + Transferable> Deque<T, A> implements Transferable {}
unsafe extend<T: Shareable, A: Allocator + Shareable> Deque<T, A> implements Shareable {}
