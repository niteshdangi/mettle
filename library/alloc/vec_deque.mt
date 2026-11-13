import core.iter.{Iterator, BidirectionalIterator, ExactSizeIterator, FusedIterator, Bound, RangeBounds, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems}
import core.clone.Clone
import core.default.Default
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.hash.{Hash, Hasher}
import core.fmt

import super.alloc.{Allocator, Global, AllocError, PushError, layout_unchecked, handle_alloc_error, layout_of, dangling_for, free_block}

copy type RawSlice<T> { data: ptr<read T>; len: usize }

fn ring_index(head: usize, logical: usize, capacity: usize): usize {
    let until_wrap = capacity - head
    if logical >= until_wrap { logical - until_wrap } else { head + logical }
}

// Safety: slots[start..end] is a live exclusive MaybeUninit<T> extent.
unsafe fn reverse_slots<T>(slots: ptr<mut core.mem.MaybeUninit<T>>, start: usize, end: usize): Unit {
    var front = start
    var back = end
    while front < back {
        back -= 1usize
        if front == back { break }
        core.ptr.swap(slots.add(front), slots.add(back))
        front += 1usize
    }
}

// Safety: `p` is aligned and valid for reads of `n` initialized elements.
unsafe fn slice_ptr<T>(p: ptr<mut T>, n: usize): ptr<read [T]> {
    unsafe { core.mem.transmute<ptr<read [T]>>(RawSlice(p.cast_const(), n)) }
}
// Safety: `p` is aligned and valid for exclusive access to `n` elements.
unsafe fn slice_ptr_mut<T>(p: ptr<mut T>, n: usize): ptr<mut [T]> {
    unsafe { core.mem.transmute<ptr<mut [T]>>(RawSlice(p.cast_const(), n)) }
}

// Safety invariant: `buf` and `len` remain valid for the deque, and `head`,
// `cap`, and the allocation do not change while the guard is active. At unwind
// points `[0, kept)` and `[read_at, total)` own values; the gap contains only
// rejected values being destroyed or logically moved-from slots. `total` is
// at most `cap`, so forward compaction cannot overwrite a future source. ZST
// copies touch no bytes; the restored length controls their drop count.
type RetainGuard<T> {
    buf: ptr<mut T>
    cap: usize
    head: usize
    len: ptr<mut usize>
    total: usize
    read_at: usize
    kept: usize
    active: bool
    drop {
        if self.active {
            var i = self.read_at
            while i < self.total {
                let dst_index = self.kept + (i - self.read_at)
                if dst_index != i {
                    let src = unsafe { self.buf.add(self.physical(i)) }
                    let dst = unsafe { self.buf.add(self.physical(dst_index)) }
                    unsafe { core.ptr.`copy`(src.cast_const(), dst, 1usize) }
                }
                i += 1usize
            }
            unsafe {
                core.ptr.write(self.len, self.kept + (self.total - self.read_at))
            }
        }
    }
}

extend<T> RetainGuard<T> {
    fn physical(i: usize): usize {
        ring_index(self.head, i, self.cap)
    }

    mut fn finish(): Unit {
        unsafe { core.ptr.write(self.len, self.kept) }
        self.active = false
    }
}

// Growable ring buffer owning its block and allocator.
pub type Deque<T, A: Allocator = Global> {
    buf: ptr<mut T>
    cap: usize
    head: usize
    len: usize
    a: A
    drop {
        let n = self.len
        self.len = 0usize
        let layout = unsafe { layout_unchecked(self.cap * core.mem.size_of<T>(), core.mem.align_of<T>()) }
        let _free = unsafe { free_block(self.buf.cast<u8>(), layout, core.ptr.from_mut(self.a)) }
        var remaining = DequeDrop(self.buf, self.cap, self.head, n)
        remaining.run()
    }
}

// Safety: remaining initialized ring slots are exclusively owned until the outer free-block guard runs.
type DequeDrop<T> {
    buf: ptr<mut T>
    cap: usize
    head: usize
    remaining: usize
    drop { self.run() }
}

extend<T> DequeDrop<T> {
    mut fn run(): Unit {
        while self.remaining != 0usize {
            let at = self.head
            self.head = ring_index(self.head, 1usize, self.cap)
            self.remaining -= 1usize
            unsafe { core.ptr.drop_in_place(self.buf.add(at)) }
        }
    }
}

// Restores the retained tail even when dropping an unyielded drained value
// unwinds. The active drain borrow keeps the ring allocation and head stable.
type DequeDrainFinish<T> {
    buf: ptr<mut T>
    cap: usize
    head: usize
    head_ptr: ptr<mut usize>
    len: ptr<mut usize>
    start: usize
    front: usize
    back: usize
    tail_start: usize
    tail_len: usize
    drop {
        self.drop_remaining()
        let removed = self.tail_start - self.start
        if self.start <= self.tail_len {
            var i = 0usize
            while i < self.tail_len {
                let source = self.physical(self.tail_start + i)
                let destination = self.physical(self.start + i)
                if source != destination {
                    // Safety: the drained range is dead; copying the tail
                    // left in forward order does not overwrite a future source.
                    unsafe {
                        core.ptr.`copy`(
                            self.buf.add(source).cast_const(),
                            self.buf.add(destination),
                            1usize
                        )
                    }
                }
                i += 1usize
            }
        } else {
            // Move the shorter prefix right, from back to front, then advance
            // head so the unchanged suffix follows it in logical order.
            var i = self.start
            while i != 0usize {
                i -= 1usize
                let source = self.physical(i)
                let destination = self.physical(i + removed)
                if source != destination {
                    // Safety: reverse order preserves sources during this
                    // rightward overlapping move; drained slots are unowned.
                    unsafe {
                        core.ptr.`copy`(
                            self.buf.add(source).cast_const(),
                            self.buf.add(destination),
                            1usize
                        )
                    }
                }
            }
            unsafe {
                core.ptr.write(
                    self.head_ptr,
                    ring_index(self.head, removed, self.cap)
                )
            }
        }
        unsafe { core.ptr.write(self.len, self.start + self.tail_len) }
    }
}

extend<T> DequeDrainFinish<T> {
    fn physical(logical: usize): usize {
        ring_index(self.head, logical, self.cap)
    }

    mut fn drop_remaining(): Unit {
        while self.front < self.back {
            let index = self.front
            self.front += 1usize
            let at = self.physical(index)
            unsafe { core.ptr.drop_in_place(self.buf.add(at)) }
        }
    }
}

pub fn new_in<T, A: Allocator>(take a: A): Deque<T, A> {
    let cap = if core.mem.size_of<T>() == 0usize { 0xffffffffffffffffusize } else { 0usize }
    Deque(dangling_for<T>(), cap, 0usize, 0usize, a)
}
pub fn new<T>(): Deque<T> { new_in(Global()) }
pub fn with_capacity<T>(capacity: usize): Deque<T> {
    var deque = new<T>()
    deque.reserve_exact(capacity)
    deque
}

extend<T, A: Allocator> Deque<T, A> {
    pub fn len(): usize { self.len }
    pub fn capacity(): usize { self.cap }
    pub fn is_empty(): bool { self.len == 0usize }
    pub fn allocator(): read A from self { read self.a }

    fn physical(i: usize): usize {
        ring_index(self.head, i, self.cap)
    }

    // Moves the elements to the front of a larger block; failure changes nothing.
    mut fn grow_to(need: usize, exact: bool): Unit throws AllocError {
        let size = core.mem.size_of<T>()
        if size == 0usize || need <= self.cap { return () }
        var ncap = need
        if !exact {
            let doubled = self.cap.saturating_mul(2usize)
            if doubled > ncap { ncap = doubled }
            if ncap < 4usize { ncap = 4usize }
        }
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
        let old_buf = self.buf
        let old_cap = self.cap
        self.buf = np
        self.cap = ncap
        self.head = 0usize
        if old_cap != 0usize {
            unsafe { self.a.deallocate(old_buf.cast<u8>(), layout_unchecked(old_cap * size, align)) }
        }
    }
    pub mut fn try_reserve(additional: usize): Unit throws AllocError {
        let need = match self.len.checked_add(additional) {
            present(n) => n,
            none => throw AllocError(0xffffffffffffffffusize, core.mem.align_of<T>())
        }
        try self.grow_to(need, false)
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
        let need = match self.len.checked_add(additional) {
            present(n) => n,
            none => throw AllocError(0xffffffffffffffffusize, core.mem.align_of<T>())
        }
        try self.grow_to(need, true)
    }
    pub mut fn reserve_exact(additional: usize): Unit {
        match capture self.try_reserve_exact(additional) {
            success(_) => (),
            failure(_) => handle_alloc_error(layout_of<T>())
        }
    }
    pub mut fn append(mut other: Deque<T, A>): Unit {
        let count = other.len
        if count == 0usize { return () }
        // Grow only with this deque's allocator before moving any values.
        self.reserve(count)
        while other.len != 0usize {
            self.push_back(other.pop_front().unwrap())
        }
    }
    pub mut fn shrink_to_fit(): Unit { self.shrink_to(0usize) }
    pub mut fn shrink_to(min_capacity: usize): Unit {
        let size = core.mem.size_of<T>()
        let target = if min_capacity < self.len { self.len } else { min_capacity }
        if size == 0usize || self.cap <= target { return () }
        let align = core.mem.align_of<T>()
        if target == 0usize {
            let old_buf = self.buf
            let old_cap = self.cap
            self.buf = dangling_for<T>()
            self.cap = 0usize
            self.head = 0usize
            unsafe { self.a.deallocate(old_buf.cast<u8>(), layout_unchecked(old_cap * size, align)) }
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
        let old_buf = self.buf
        let old_cap = self.cap
        self.buf = new_buf
        self.cap = target
        self.head = 0usize
        unsafe { self.a.deallocate(old_buf.cast<u8>(), layout_unchecked(old_cap * size, align)) }
    }
    pub mut fn try_push_back(take value: T): Unit throws PushError<T> {
        match capture self.try_reserve_one() {
            success(_) => {},
            failure(error) => { throw PushError(value, error) }
        }
        let at = self.physical(self.len)
        unsafe { core.ptr.write(self.buf.add(at), value) }
        self.len += 1usize
    }
    pub mut fn try_push_front(take value: T): Unit throws PushError<T> {
        match capture self.try_reserve_one() {
            success(_) => {},
            failure(error) => { throw PushError(value, error) }
        }
        self.head = if self.head == 0usize { self.cap - 1usize } else { self.head - 1usize }
        unsafe { core.ptr.write(self.buf.add(self.head), value) }
        self.len += 1usize
    }
    pub mut fn push_back(take value: T): Unit {
        match capture self.try_reserve_one() {
            success(_) => {},
            failure(_) => handle_alloc_error(layout_of<T>())
        }
        let at = self.physical(self.len)
        unsafe { core.ptr.write(self.buf.add(at), value) }
        self.len += 1usize
    }
    pub mut fn push_back_mut(take value: T): mut T from self {
        self.push_back(value)
        self.get_mut(self.len - 1usize).unwrap()
    }
    pub mut fn push_front(take value: T): Unit {
        match capture self.try_reserve_one() {
            success(_) => {},
            failure(_) => handle_alloc_error(layout_of<T>())
        }
        self.head = if self.head == 0usize { self.cap - 1usize } else { self.head - 1usize }
        unsafe { core.ptr.write(self.buf.add(self.head), value) }
        self.len += 1usize
    }
    pub mut fn push_front_mut(take value: T): mut T from self {
        self.push_front(value)
        self.get_mut(0usize).unwrap()
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
    pub mut fn pop_front_if<F: take fn(mut T): bool>(take test: F): T? {
        if self.len == 0usize { return none }
        let first = self.get_mut(0usize).unwrap()
        if test(first) { self.pop_front() } else { none }
    }
    pub mut fn pop_back_if<F: take fn(mut T): bool>(take test: F): T? {
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
    pub mut fn swap(i: usize, j: usize): Unit {
        if i >= self.len || j >= self.len {
            super.alloc.panic_precondition()
        }
        if i != j {
            unsafe {
                core.ptr.swap(
                    self.buf.add(self.physical(i)),
                    self.buf.add(self.physical(j))
                )
            }
        }
    }
    pub fn binary_search_by<F: mut fn(read T): Ordering>(take compare: F): usize throws usize {
        var comparator = take compare
        var low = 0usize
        var high = self.len
        while low < high {
            let mid = low + (high - low) / 2usize
            let order = comparator(self.get(mid).unwrap())
            if order.is_lt() {
                low = mid + 1usize
            } else {
                if order.is_gt() { high = mid } else { return mid }
            }
        }
        throw low
    }
    pub fn binary_search_by_key<K: Ord, F: mut fn(read T): K>(
        read key: K,
        take project: F
    ): usize throws usize {
        var key_fn = take project
        var low = 0usize
        var high = self.len
        while low < high {
            let mid = low + (high - low) / 2usize
            let current = key_fn(self.get(mid).unwrap())
            let order = current.cmp(key)
            if order.is_lt() {
                low = mid + 1usize
            } else {
                if order.is_gt() { high = mid } else { return mid }
            }
        }
        throw low
    }
    pub fn partition_point<F: mut fn(read T): bool>(take before: F): usize {
        var predicate = take before
        var low = 0usize
        var high = self.len
        while low < high {
            let mid = low + (high - low) / 2usize
            if predicate(self.get(mid).unwrap()) {
                low = mid + 1usize
            } else {
                high = mid
            }
        }
        low
    }
    pub mut fn insert(i: usize, take value: T): Unit {
        if i > self.len { super.alloc.panic_precondition() }
        if i == 0usize { self.push_front(value); return () }
        if i == self.len { self.push_back(value); return () }
        self.reserve(1usize)
        if i < self.len - i {
            self.head = if self.head == 0usize { self.cap - 1usize } else { self.head - 1usize }
            var j = 0usize
            while j < i {
                unsafe {
                    core.ptr.`copy`(
                        self.buf.add(self.physical(j + 1usize)).cast_const(),
                        self.buf.add(self.physical(j)),
                        1usize
                    )
                }
                j += 1usize
            }
        } else {
            var j = self.len
            while j > i {
                unsafe {
                    core.ptr.`copy`(
                        self.buf.add(self.physical(j - 1usize)).cast_const(),
                        self.buf.add(self.physical(j)),
                        1usize
                    )
                }
                j -= 1usize
            }
        }
        unsafe { core.ptr.write(self.buf.add(self.physical(i)), value) }
        self.len += 1usize
    }
    pub mut fn insert_mut(i: usize, take value: T): mut T from self {
        self.insert(i, value)
        self.get_mut(i).unwrap()
    }
    pub mut fn remove(i: usize): T? {
        if i >= self.len { return none }
        let value = unsafe { core.ptr.`read`(self.buf.add(self.physical(i))) }
        if i < self.len - i - 1usize {
            var j = i
            while j != 0usize {
                unsafe {
                    core.ptr.`copy`(
                        self.buf.add(self.physical(j - 1usize)).cast_const(),
                        self.buf.add(self.physical(j)),
                        1usize
                    )
                }
                j -= 1usize
            }
            self.head = self.physical(1usize)
        } else {
            var j = i
            while j + 1usize < self.len {
                unsafe {
                    core.ptr.`copy`(
                        self.buf.add(self.physical(j + 1usize)).cast_const(),
                        self.buf.add(self.physical(j)),
                        1usize
                    )
                }
                j += 1usize
            }
        }
        self.len -= 1usize
        present(value)
    }
    pub mut fn swap_remove_front(i: usize): T? {
        if i >= self.len { return none }
        if i != 0usize {
            unsafe { core.ptr.swap(self.buf.add(self.head), self.buf.add(self.physical(i))) }
        }
        self.pop_front()
    }
    pub mut fn swap_remove_back(i: usize): T? {
        if i >= self.len { return none }
        let last = self.len - 1usize
        if i != last {
            unsafe { core.ptr.swap(self.buf.add(self.physical(i)), self.buf.add(self.physical(last))) }
        }
        self.pop_back()
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
        if mid > self.len - mid {
            self.rotate_right(self.len - mid)
            return ()
        }
        var i = 0usize
        while i < mid {
            let value = self.pop_front().unwrap()
            self.push_back(value)
            i += 1usize
        }
    }
    pub mut fn rotate_right(mid: usize): Unit {
        if mid > self.len { super.alloc.panic_precondition() }
        if mid > self.len - mid {
            self.rotate_left(self.len - mid)
            return ()
        }
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
        let first = self.cap - self.head
        let second = self.len - first
        let free = self.cap - self.len
        if free >= first {
            unsafe {
                core.ptr.`copy`(self.buf.cast_const(), self.buf.add(first), second)
                core.ptr.`copy`(self.buf.add(self.head).cast_const(), self.buf, first)
            }
            self.head = 0usize
        } else if free >= second {
            let head = self.head - second
            unsafe {
                core.ptr.`copy`(self.buf.add(self.head).cast_const(), self.buf.add(head), first)
                core.ptr.`copy`(self.buf.cast_const(), self.buf.add(self.cap - second), second)
            }
            self.head = head
        } else {
            // Here cap < 3*len/2; rotating MaybeUninit slots is O(len) and never reads spare bytes as T.
            let slots = self.buf.cast<core.mem.MaybeUninit<T>>()
            unsafe {
                reverse_slots(slots, 0usize, self.head)
                reverse_slots(slots, self.head, self.cap)
                reverse_slots(slots, 0usize, self.cap)
            }
            self.head = 0usize
        }
        unsafe { mut *slice_ptr_mut(self.buf.add(self.head), self.len) }
    }
    // The guard compacts the unvisited suffix on unwind. `read_at` excludes a
    // rejected value before its destructor runs; `kept` counts moved owners.
    // The ring bounds and head stay fixed for the guard's lifetime, and the
    // copied-from slots are outside the restored initialized prefix.
    pub mut fn retain<F: mut fn(read T): bool>(mut keep: F): Unit {
        let n = self.len
        var guard = RetainGuard<T>(
            self.buf,
            self.cap,
            self.head,
            core.ptr.from_mut(self.len),
            n,
            0usize,
            0usize,
            true
        )
        var read_at = 0usize
        while read_at < n {
            let p = unsafe { self.buf.add(self.physical(read_at)) }
            let alive = keep(unsafe { read *p })
            read_at += 1usize
            guard.read_at = read_at
            if alive {
                if guard.kept != read_at - 1usize {
                    let dst = unsafe { self.buf.add(self.physical(guard.kept)) }
                    unsafe { core.ptr.`copy`(p.cast_const(), dst, 1usize) }
                }
                guard.kept += 1usize
            } else {
                unsafe { core.ptr.drop_in_place(p) }
            }
        }
        guard.finish()
    }

    pub mut fn retain_mut<F: mut fn(mut T): bool>(mut keep: F): Unit {
        let n = self.len
        var guard = RetainGuard<T>(
            self.buf,
            self.cap,
            self.head,
            core.ptr.from_mut(self.len),
            n,
            0usize,
            0usize,
            true
        )
        var read_at = 0usize
        while read_at < n {
            let p = unsafe { self.buf.add(self.physical(read_at)) }
            let alive = keep(unsafe { mut *p })
            read_at += 1usize
            guard.read_at = read_at
            if alive {
                if guard.kept != read_at - 1usize {
                    let dst = unsafe { self.buf.add(self.physical(guard.kept)) }
                    unsafe { core.ptr.`copy`(p.cast_const(), dst, 1usize) }
                }
                guard.kept += 1usize
            } else {
                unsafe { core.ptr.drop_in_place(p) }
            }
        }
        guard.finish()
    }
    pub mut fn range_mut(start: usize, end: usize): DequeRangeMut<region self, T, A> {
        if start > end || end > self.len { super.alloc.panic_precondition() }
        DequeRangeMut(mut self, start, end)
    }
    pub fn range(start: usize, end: usize): DequeIter<region self, T, A> {
        if start > end || end > self.len { super.alloc.panic_precondition() }
        DequeIter(present(read self), start, end)
    }
    pub mut fn drain<R: RangeBounds<usize>>(take range: R): DequeDrain<region self, T, A> {
        let start = match R.(RangeBounds<usize>).start_bound(read range) {
            Bound.Included(value) => *value,
            Bound.Excluded(value) => match (*value).checked_add(1usize) {
                present(index) => index,
                none => super.alloc.panic_precondition()
            },
            Bound.Unbounded => 0usize
        }
        let end = match R.(RangeBounds<usize>).end_bound(read range) {
            Bound.Excluded(value) => *value,
            Bound.Included(value) => match (*value).checked_add(1usize) {
                present(index) => index,
                none => super.alloc.panic_precondition()
            },
            Bound.Unbounded => self.len
        }
        self.drain_bounds(start, end)
    }
    // The RangeBounds entry point normalizes its bounds before calling this.
    // Keeping len at the prefix makes a forgotten drain memory-safe.
    mut fn drain_bounds(start: usize, end: usize): DequeDrain<region self, T, A> {
        if start > end || end > self.len { super.alloc.panic_precondition() }
        let tail_len = self.len - end
        self.len = start
        DequeDrain(mut self, start, start, end, end, tail_len)
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
    pub mut fn resize_with<F: mut fn(): T>(n: usize, take generate: F): Unit {
        if n < self.len {
            while self.len > n { let value = self.pop_back() }
            return ()
        }
        self.reserve(n - self.len)
        var generator = take generate
        while self.len < n { self.push_back(generator()) }
    }
    pub mut fn truncate(n: usize): Unit {
        while self.len > n { let value = self.pop_back() }
    }
    pub mut fn retain_back(n: usize): Unit {
        while self.len > n { let value = self.pop_front() }
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

extend<T: Ord, A: Allocator> Deque<T, A> {
    pub fn binary_search(read value: T): usize throws usize {
        try self.binary_search_by(fn(read item: T): Ordering { item.cmp(value) })
    }
}

extend<T: PartialEq, A: Allocator> Deque<T, A> {
    pub fn contains(read value: T): bool {
        var index = 0usize
        while index < self.len {
            if self[index].eq(value) { return true }
            index += 1usize
        }
        false
    }
}

extend<T: Clone, A: Allocator> Deque<T, A> {
    pub mut fn resize(n: usize, read value: T): Unit {
        if n <= self.len {
            self.truncate(n)
            return ()
        }
        self.reserve(n - self.len)
        while self.len < n { self.push_back(value.clone()) }
    }
}

extend<T, A: Allocator + Default> Deque<T, A> implements Default {
    static fn default(): Deque<T, A> { new_in(A.(Default).default()) }
}

extend<T, A: Allocator> Deque<T, A> implements core.ops.Index<usize> {
    type Output = T
    fn index(read i: usize): read T from self {
        if i >= self.len { super.alloc.panic_precondition() }
        unsafe { read *self.buf.add(self.physical(i)) }
    }
}
extend<T, A: Allocator> Deque<T, A> implements core.ops.IndexMut<usize> {
    type Output = T
    mut fn index_mut(read i: usize): mut T from self {
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
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.front
        (remaining, present(remaining))
    }
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
extend<region r, T, A: Allocator> DequeRangeMut<region r, T, A> implements ExactSizeIterator {}
extend<region r, T, A: Allocator> DequeRangeMut<region r, T, A> implements FusedIterator {}

pub type DequeDrain<region r, T, A: Allocator> {
    deque: mut Deque<T, A> from r
    start: usize
    front: usize
    back: usize
    tail_start: usize
    tail_len: usize
    drop {
        var finish = DequeDrainFinish(
            self.deque.buf,
            self.deque.cap,
            self.deque.head,
            core.ptr.from_mut(self.deque.head),
            core.ptr.from_mut(self.deque.len),
            self.start,
            self.front,
            self.back,
            self.tail_start,
            self.tail_len
        )
        finish.drop_remaining()
    }
}

extend<region r, T, A: Allocator> DequeDrain<region r, T, A> implements Iterator {
    type Item = T
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.front
        (remaining, present(remaining))
    }
    mut fn next(): T? {
        if self.front == self.back { return none }
        let index = self.front
        self.front += 1usize
        present(unsafe {
            core.ptr.`read`(self.deque.buf.add(self.deque.physical(index)))
        })
    }
}
extend<region r, T, A: Allocator> DequeDrain<region r, T, A> implements BidirectionalIterator {
    mut fn next_back(): T? {
        if self.front == self.back { return none }
        self.back -= 1usize
        present(unsafe {
            core.ptr.`read`(self.deque.buf.add(self.deque.physical(self.back)))
        })
    }
}
extend<region r, T, A: Allocator> DequeDrain<region r, T, A> implements ExactSizeIterator {}
extend<region r, T, A: Allocator> DequeDrain<region r, T, A> implements FusedIterator {}
extend<region r, T: fmt.Debug, A: Allocator> DequeDrain<region r, T, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("DequeDrain(")
        try f.debug_open("[")
        var i = self.front
        while i < self.back {
            let value = unsafe { read *self.deque.buf.add(self.deque.physical(i)) }
            try f.debug_item_start(i == self.front)
            try T.(fmt.Debug).fmt(value, mut f)
            try f.debug_item_end()
            i += 1usize
        }
        try f.debug_close("]", self.front == self.back)
        try f.write_str(")")
    }
}

// Borrowed front-to-back iterator over a ring buffer.
pub type DequeIter<region r, T, A: Allocator> {
    deque: (read Deque<T, A> from r)?
    front: usize
    back: usize
}
extend<region r, T, A: Allocator> DequeIter<region r, T, A> implements Iterator {
    type Item = read T from r
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.front
        (remaining, present(remaining))
    }
    mut fn next(): (read T from r)? {
        if self.front < self.back {
            let i = self.front
            self.front += 1usize
            match read self.deque {
                present(deque) => present(unsafe { read *deque.buf.add(deque.physical(i)) }),
                none => none
            }
        } else {
            none
        }
    }
}
extend<region r, T, A: Allocator> DequeIter<region r, T, A> implements BidirectionalIterator {
    mut fn next_back(): (read T from r)? {
        if self.front == self.back { return none }
        self.back -= 1usize
        match read self.deque {
            present(deque) => present(unsafe { read *deque.buf.add(deque.physical(self.back)) }),
            none => none
        }
    }
}
extend<region r, T, A: Allocator> DequeIter<region r, T, A> implements ExactSizeIterator {}
extend<region r, T, A: Allocator> DequeIter<region r, T, A> implements FusedIterator {}
extend<region r, T, A: Allocator> DequeIter<region r, T, A> implements Clone {
    fn clone(): DequeIter<region r, T, A> { DequeIter(self.deque, self.front, self.back) }
}
extend<region r, T, A: Allocator> DequeIter<region r, T, A> implements Default {
    static fn default(): DequeIter<region r, T, A> { DequeIter(none, 0usize, 0usize) }
}
extend<region r, T: fmt.Debug, A: Allocator> DequeIter<region r, T, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("Iter(")
        try f.debug_open("[")
        var index = self.front
        while index < self.back {
            match read self.deque {
                present(deque) => {
                    try f.debug_item_start(index == self.front)
                    try T.(fmt.Debug).fmt(unsafe { read *deque.buf.add(deque.physical(index)) }, mut f)
                    try f.debug_item_end()
                },
                none => { break }
            }
            index += 1usize
        }
        try f.debug_close("]", self.front == self.back)
        try f.write_str(")")
    }
}
extend<T, A: Allocator> Deque<T, A> implements Iterable {
    type Item = T
    type Iter<region r> = DequeIter<region r, T, A>
    fn iter<region r>(receiver read self: Self from r): DequeIter<region r, T, A> {
        DequeIter(present(read self), 0usize, self.len)
    }
}

// Mutable front-to-back iterator over a ring buffer.
pub type DequeIterMut<region r, T, A: Allocator> {
    deque: (mut Deque<T, A> from r)?
    front: usize
    back: usize
}
extend<region r, T, A: Allocator> DequeIterMut<region r, T, A> implements Iterator {
    type Item = mut T from r
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.front
        (remaining, present(remaining))
    }
    mut fn next(): (mut T from r)? {
        if self.front < self.back {
            let i = self.front
            self.front += 1usize
            match mut self.deque {
                present(deque) => present(unsafe { mut *deque.buf.add(deque.physical(i)) }),
                none => none
            }
        } else {
            none
        }
    }
}
extend<region r, T, A: Allocator> DequeIterMut<region r, T, A> implements BidirectionalIterator {
    mut fn next_back(): (mut T from r)? {
        if self.front == self.back { return none }
        self.back -= 1usize
        match mut self.deque {
            present(deque) => present(unsafe { mut *deque.buf.add(deque.physical(self.back)) }),
            none => none
        }
    }
}
extend<region r, T, A: Allocator> DequeIterMut<region r, T, A> implements ExactSizeIterator {}
extend<region r, T, A: Allocator> DequeIterMut<region r, T, A> implements FusedIterator {}
extend<region r, T, A: Allocator> DequeIterMut<region r, T, A> implements Default {
    static fn default(): DequeIterMut<region r, T, A> { DequeIterMut(none, 0usize, 0usize) }
}
extend<region r, T: fmt.Debug, A: Allocator> DequeIterMut<region r, T, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("IterMut(")
        try f.debug_open("[")
        match read self.deque {
            present(deque) => {
                var index = self.front
                while index < self.back {
                    try f.debug_item_start(index == self.front)
                    try T.(fmt.Debug).fmt(unsafe { read *deque.buf.add(deque.physical(index)) }, mut f)
                    try f.debug_item_end()
                    index += 1usize
                }
            },
            none => {}
        }
        try f.debug_close("]", self.front == self.back)
        try f.write_str(")")
    }
}
extend<T, A: Allocator> Deque<T, A> implements MutableIterable {
    type Item = T
    type IterMut<region r> = DequeIterMut<region r, T, A>
    fn iter_mut<region r>(receiver mut self: Self from r): DequeIterMut<region r, T, A> {
        let n = self.len
        DequeIterMut(present(mut self), 0usize, n)
    }
}

pub type DequeIntoIter<T, A: Allocator = Global> { deque: Deque<T, A> }
extend<T, A: Allocator> DequeIntoIter<T, A> implements Iterator {
    type Item = T
    fn size_hint(): (usize, usize?) {
        let remaining = self.deque.len
        (remaining, present(remaining))
    }
    mut fn next(): T? { self.deque.pop_front() }
}
extend<T, A: Allocator> DequeIntoIter<T, A> implements BidirectionalIterator {
    mut fn next_back(): T? { self.deque.pop_back() }
}
extend<T, A: Allocator> DequeIntoIter<T, A> implements ExactSizeIterator {}
extend<T, A: Allocator> DequeIntoIter<T, A> implements FusedIterator {}
extend<T: fmt.Debug, A: Allocator> DequeIntoIter<T, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("DequeIntoIter(")
        try Deque<T, A>.(fmt.Debug).fmt(read self.deque, mut f)
        try f.write_str(")")
    }
}
extend<T: Clone, A: Allocator + Clone> DequeIntoIter<T, A> implements Clone {
    fn clone(): DequeIntoIter<T, A> { DequeIntoIter(self.deque.clone()) }
}
extend<T, A: Allocator + Default> DequeIntoIter<T, A> implements Default {
    static fn default(): DequeIntoIter<T, A> {
        DequeIntoIter(new_in<T, A>(A.(Default).default()))
    }
}
extend<T, A: Allocator> Deque<T, A> implements OwnedIterable {
    type Item = T
    type IntoIter = DequeIntoIter<T, A>
    fn into_iter(receiver take self: Self): DequeIntoIter<T, A> {
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
    fn eq(read other: Deque<T, A>): bool {
        if self.len != other.len { return false }
        var i = 0usize
        while i < self.len {
            if !self[i].eq(other[i]) { return false }
            i += 1usize
        }
        true
    }
}
extend<T: PartialEq<U>, U, A: Allocator> Deque<T, A> implements PartialEq<[U]> {
    fn eq(read other: [U]): bool {
        if self.len != other.len() { return false }
        var i = 0usize
        while i < self.len {
            if !self[i].eq(other[i]) { return false }
            i += 1usize
        }
        true
    }
}
extend<T: PartialEq<U>, U, A: Allocator> Deque<T, A> implements PartialEq<super.vec.List<U, A>> {
    fn eq(read other: super.vec.List<U, A>): bool {
        if self.len != other.len() { return false }
        var i = 0usize
        while i < self.len {
            if !self[i].eq(other[i]) { return false }
            i += 1usize
        }
        true
    }
}
extend<T: Eq, A: Allocator> Deque<T, A> implements Eq {}
extend<region r, T: PartialEq<U>, U, A: Allocator> Deque<T, A> implements PartialEq<read [U] from r> {
    fn eq(read other: read [U] from r): bool {
        Deque<T, A>.(PartialEq<[U]>).eq(self, *other)
    }
}
extend<region r, T: PartialEq<U>, U, A: Allocator> Deque<T, A> implements PartialEq<mut [U] from r> {
    fn eq(read other: mut [U] from r): bool {
        Deque<T, A>.(PartialEq<[U]>).eq(self, *other)
    }
}
extend<T: PartialEq<U>, U, A: Allocator, const N: usize> Deque<T, A> implements PartialEq<[U; N]> {
    fn eq(read other: [U; N]): bool {
        let items: read [U] = read other
        Deque<T, A>.(PartialEq<[U]>).eq(self, items)
    }
}
extend<region r, T: PartialEq<U>, U, A: Allocator, const N: usize> Deque<T, A> implements PartialEq<read [U; N] from r> {
    fn eq(read other: read [U; N] from r): bool {
        let items: read [U] = read *other
        Deque<T, A>.(PartialEq<[U]>).eq(self, items)
    }
}
extend<region r, T: PartialEq<U>, U, A: Allocator, const N: usize> Deque<T, A> implements PartialEq<mut [U; N] from r> {
    fn eq(read other: mut [U; N] from r): bool {
        let items: read [U] = read *other
        Deque<T, A>.(PartialEq<[U]>).eq(self, items)
    }
}
extend<T: PartialOrd, A: Allocator> Deque<T, A> implements PartialOrd {
    fn partial_cmp(read other: Deque<T, A>): Ordering? {
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
    fn cmp(read other: Deque<T, A>): Ordering {
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
    fn hash<H: Hasher>(mut state: H): Unit {
        state.write_usize(self.len)
        var i = 0usize
        while i < self.len {
            self[i].hash(mut state)
            i += 1usize
        }
    }
}
extend<T: fmt.Debug, A: Allocator> Deque<T, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
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
    mut fn extend<I: OwnedIterable<Item = T>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { self.push_back(item) }, none => { break } }
        }
    }
}
extend<region r, T: Copy, A: Allocator> Deque<T, A> implements ExtendItems<read T from r> {
    mut fn extend<I: OwnedIterable<Item = read T from r>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(item) => { self.push_back(*item) },
                none => { break }
            }
        }
    }
}
extend<T> Deque<T> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(take items: I): Deque<T> {
        var out = new<T>()
        out.extend(items)
        out
    }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<T: Transferable, A: Allocator + Transferable> Deque<T, A> implements Transferable {}
unsafe extend<T: Shareable, A: Allocator + Shareable> Deque<T, A> implements Shareable {}

extend<T, A: Allocator> Deque<T, A> implements core.convert.From<super.vec.List<T, A>> {
    static fn from(take source: super.vec.List<T, A>): Deque<T, A> {
        let parts = source.into_raw_parts_with_alloc()
        Deque(parts.0, parts.2, 0usize, parts.1, parts.3)
    }
}

extend<T, const N: usize> Deque<T> implements core.convert.From<[T; N]> {
    static fn from(take items: [T; N]): Deque<T> {
        let list = super.vec.List<T>.(core.convert.From<[T; N]>).from(items)
        Deque<T>.(core.convert.From<super.vec.List<T>>).from(list)
    }
}

// The ring is rotated in place to start at slot zero, then its allocation is
// adopted by the list (same layout, no element copies beyond the rotation).
extend<T, A: Allocator> super.vec.List<T, A> implements core.convert.From<Deque<T, A>> {
    static fn from(take source: Deque<T, A>): super.vec.List<T, A> {
        var ring = take source
        ring.make_contiguous()
        let size = core.mem.size_of<T>()
        unsafe {
            if ring.head != 0usize && ring.len != 0usize {
                core.ptr.`copy`(ring.buf.add(ring.head).cast_const(), ring.buf, ring.len)
            }
            let pointer = ring.buf
            let length = ring.len
            let capacity = if size == 0usize { 0xffffffffffffffffusize } else { ring.cap }
            let allocator = core.ptr.`read`(core.ptr.from_ref(ring.a))
            core.mem.forget(take ring)
            super.vec.List<T, A>.from_raw_parts_in(pointer, length, capacity, allocator)
        }
    }
}
