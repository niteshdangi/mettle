import super.alloc.{Allocator, Global, AllocError, Layout, layout_of, layout_unchecked, free_block, handle_alloc_error, panic_precondition, dangling_for}
import package.core.clone.Clone
import package.core.default.Default
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.hash.{Hash, Hasher}
import package.core.fmt
import package.core.ops.{Deref, DerefMut, IndexRange, IndexRangeMut}
import package.core.iter.{Iterator, BidirectionalIterator, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems}
import package.core.slice.{SliceIter, SliceIterMut}

copy type RawSlice<T> { data: ptr<read T>; len: usize }

// Slice pointers carry no region; callers turn them into views anchored to
// the owner's own storage.
pub fn slice_ptr<T>(p: ptr<mut T>, n: usize): ptr<read [T]> {
    let raw = RawSlice(p.cast_const(), n)
    unsafe { core.mem.transmute<ptr<read [T]>>(raw) }
}
pub fn slice_ptr_mut<T>(p: ptr<mut T>, n: usize): ptr<mut [T]> {
    let raw = RawSlice(p.cast_const(), n)
    unsafe { core.mem.transmute<ptr<mut [T]>>(raw) }
}

// Drops `n` consecutive values. If one destructor panics the guard's own
// destructor still drops the rest.
type DropRun<T> {
    p: ptr<mut T>
    n: usize
    drop {
        while self.n != 0usize {
            let current = self.p
            self.p = unsafe { self.p.add(1usize) }
            self.n -= 1usize
            unsafe { core.ptr.drop_in_place(current) }
        }
    }
}

pub fn drop_run<T>(p: ptr<mut T>, n: usize): Unit {
    let _guard = DropRun(p, n)
}

// Contiguous growable array owning its buffer and the allocator that made it.
pub type List<T, A: Allocator = Global> {
    ptr: ptr<mut T>
    len: usize
    cap: usize
    a: A
    drop {
        let n = self.len
        self.len = 0usize
        let layout = unsafe { layout_unchecked(self.cap * core.mem.size_of<T>(), core.mem.align_of<T>()) }
        let _free = unsafe { free_block(self.ptr.cast<u8>(), layout, core.ptr.from_mut(self.a)) }
        let _run = DropRun(self.ptr, n)
    }
}

pub fn new_in<T, A: Allocator>(a: take A): List<T, A> {
    List<T, A>(allocator: take a)
}
pub fn new<T>(): List<T> { new_in(Global()) }

pub fn try_with_capacity_in<T, A: Allocator>(n: usize, a: take A): List<T, A> throws AllocError {
    var v = new_in<T, A>(a)
    try v.try_reserve_exact(n)
    v
}
pub fn with_capacity_in<T, A: Allocator>(n: usize, a: take A): List<T, A> {
    var v = new_in<T, A>(a)
    v.reserve_exact(n)
    v
}
pub fn with_capacity<T>(n: usize): List<T> { with_capacity_in(n, Global()) }

extend<T> List<T> {
    pub init() {
        self.ptr = dangling_for<T>()
        self.len = 0usize
        self.cap = if core.mem.size_of<T>() == 0usize { 0xffffffffffffffffusize } else { 0usize }
        self.a = Global()
    }
}

extend<T, A: Allocator> List<T, A> {
    pub init(allocator: take A) {
        self.ptr = dangling_for<T>()
        self.len = 0usize
        self.cap = if core.mem.size_of<T>() == 0usize { 0xffffffffffffffffusize } else { 0usize }
        self.a = take allocator
    }

    pub fn len(): usize { self.len }
    pub fn capacity(): usize { self.cap }
    pub fn is_empty(): bool { self.len == 0usize }
    pub fn allocator(): read A from self { read self.a }
    pub mut fn allocator_mut(): mut A from self { mut self.a }
    pub fn as_ptr(): ptr<read T> { self.ptr.cast_const() }
    pub fn as_mut_ptr(): ptr<mut T> { self.ptr }

    // Safety: `n <= capacity` and the first `n` slots are initialized.
    pub mut unsafe fn set_len(n: usize): Unit { self.len = n }

    pub fn as_slice(): read [T] from self { unsafe { read *slice_ptr(self.ptr, self.len) } }
    pub mut fn as_mut_slice(): mut [T] from self { unsafe { mut *slice_ptr_mut(self.ptr, self.len) } }

    // Grows to at least `need` slots; failure leaves the vector unchanged.
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
        if bytes > 0x7fffffffffffffffusize - (align - 1usize) { throw AllocError(bytes, align) }
        let np = if self.cap == 0usize {
            try self.a.allocate(unsafe { layout_unchecked(bytes, align) })
        } else {
            try self.a.grow(self.ptr.cast<u8>(), unsafe { layout_unchecked(self.cap * size, align) }, bytes)
        }
        self.ptr = np.cast<T>()
        self.cap = ncap
    }
    pub mut fn try_reserve(extra: usize): Unit throws AllocError {
        match self.len.checked_add(extra) {
            present(need) => try self.grow_to(need, false),
            none => throw AllocError(0xffffffffffffffffusize, core.mem.align_of<T>())
        }
    }
    pub mut fn try_reserve_exact(extra: usize): Unit throws AllocError {
        match self.len.checked_add(extra) {
            present(need) => try self.grow_to(need, true),
            none => throw AllocError(0xffffffffffffffffusize, core.mem.align_of<T>())
        }
    }
    pub mut fn reserve(extra: usize): Unit {
        match capture self.try_reserve(extra) {
            success(_) => (),
            failure(_) => handle_alloc_error(layout_of<T>())
        }
    }
    pub mut fn reserve_exact(extra: usize): Unit {
        match capture self.try_reserve_exact(extra) {
            success(_) => (),
            failure(_) => handle_alloc_error(layout_of<T>())
        }
    }
    // Releases spare capacity; failure keeps the larger block.
    pub mut fn shrink_to_fit(): Unit { self.shrink_to(0usize) }
    pub mut fn shrink_to(min_capacity: usize): Unit {
        let size = core.mem.size_of<T>()
        let target = if min_capacity < self.len { self.len } else { min_capacity }
        if size == 0usize || self.cap <= target || self.cap == 0usize { return () }
        let align = core.mem.align_of<T>()
        let old = unsafe { layout_unchecked(self.cap * size, align) }
        match capture self.a.shrink(self.ptr.cast<u8>(), old, target * size) {
            success(np) => {
                self.ptr = np.cast<T>()
                self.cap = target
            },
            failure(_) => ()
        }
    }

    // On allocation failure the error retains the value and the vector is unchanged.
    pub mut fn try_push(value: take T): Unit throws super.alloc.PushError<T> {
        match capture self.try_reserve(1usize) {
            success(_) => {},
            failure(error) => { throw super.alloc.PushError(value, error) }
        }
        unsafe { core.ptr.write(self.ptr.add(self.len), value) }
        self.len += 1usize
    }
    pub mut fn push(value: take T): Unit {
        if self.len == self.cap { self.reserve(1usize) }
        unsafe { core.ptr.write(self.ptr.add(self.len), value) }
        self.len += 1usize
    }
    pub mut fn pop(): T? {
        if self.len == 0usize { return none }
        self.len -= 1usize
        present(unsafe { core.ptr.`read`(self.ptr.add(self.len)) })
    }
    pub mut fn insert(index: usize, value: take T): Unit {
        if index > self.len { panic_precondition() }
        if self.len == self.cap { self.reserve(1usize) }
        unsafe {
            let p = self.ptr.add(index)
            core.ptr.`copy`(p.cast_const(), p.add(1usize), self.len - index)
            core.ptr.write(p, value)
        }
        self.len += 1usize
    }
    pub mut fn remove(index: usize): T {
        if index >= self.len { panic_precondition() }
        unsafe {
            let p = self.ptr.add(index)
            let value = core.ptr.`read`(p)
            core.ptr.`copy`(p.add(1usize).cast_const(), p, self.len - index - 1usize)
            self.len -= 1usize
            value
        }
    }
    pub mut fn swap_remove(index: usize): T {
        if index >= self.len { panic_precondition() }
        unsafe {
            let p = self.ptr.add(index)
            let value = core.ptr.`read`(p)
            self.len -= 1usize
            if index != self.len { core.ptr.`copy`(self.ptr.add(self.len).cast_const(), p, 1usize) }
            value
        }
    }
    // Drops the tail; the length is lowered first so a panicking destructor
    // cannot cause a double drop.
    pub mut fn truncate(n: usize): Unit {
        if n >= self.len { return () }
        let old = self.len
        self.len = n
        drop_run(unsafe { self.ptr.add(n) }, old - n)
    }
    pub mut fn clear(): Unit { self.truncate(0usize) }

    pub mut fn drain(start: usize, end: usize): Drain<region self, T, A> {
        if start > end || end > self.len { panic_precondition() }
        let tail_len = self.len - end
        self.len = start
        Drain(mut self, start, start, end, end, tail_len)
    }

    pub fn get(index: usize): (read T from self)? {
        if index < self.len { present(unsafe { read *self.ptr.add(index) }) } else { none }
    }
    pub mut fn get_mut(index: usize): (mut T from self)? {
        if index < self.len { present(unsafe { mut *self.ptr.add(index) }) } else { none }
    }
    pub mut fn swap(i: usize, j: usize): Unit {
        if i >= self.len || j >= self.len { panic_precondition() }
        if i != j { unsafe { core.ptr.swap(self.ptr.add(i), self.ptr.add(j)) } }
    }
    pub mut fn reverse(): Unit {
        var i = 0usize
        var j = self.len
        while i + 1usize < j {
            j -= 1usize
            unsafe { core.ptr.swap(self.ptr.add(i), self.ptr.add(j)) }
            i += 1usize
        }
    }

    // Moves all elements of `other` to the end; `other` is left empty.
    pub mut fn append(other: mut List<T, A>): Unit {
        self.reserve(other.len)
        unsafe {
            core.ptr.`copy`(other.ptr.cast_const(), self.ptr.add(self.len), other.len)
        }
        self.len += other.len
        other.len = 0usize
    }

    pub mut fn split_off(at: usize): List<T, A> where A: Clone {
        if at > self.len { panic_precondition() }
        let count = self.len - at
        var other = new_in<T, A>(self.a.clone())
        other.reserve_exact(count)
        var i = 0usize
        while i < count {
            let value = unsafe { core.ptr.`read`(self.ptr.add(at + i)) }
            unsafe { core.ptr.write(other.ptr.add(i), value) }
            i += 1usize
        }
        other.len = count
        self.len = at
        other
    }

    // Keeps elements for which `keep` is true, in order. The length is zeroed
    // while running, so a panic in `keep` or a destructor leaks the rest
    // instead of exposing moved-from slots.
    pub mut fn retain(keep: fn(read T): bool): Unit {
        let n = self.len
        self.len = 0usize
        var read_at = 0usize
        var kept = 0usize
        while read_at < n {
            let p = unsafe { self.ptr.add(read_at) }
            let alive = keep(unsafe { read *p })
            read_at += 1usize
            if alive {
                if kept != read_at - 1usize { unsafe { core.ptr.`copy`(p.cast_const(), self.ptr.add(kept), 1usize) } }
                kept += 1usize
            } else {
                unsafe { core.ptr.drop_in_place(p) }
            }
        }
        self.len = kept
    }

    pub mut fn retain_mut(keep: fn(mut T): bool): Unit {
        let n = self.len
        self.len = 0usize
        var read_at = 0usize
        var kept = 0usize
        while read_at < n {
            let p = unsafe { self.ptr.add(read_at) }
            let alive = keep(unsafe { mut *p })
            read_at += 1usize
            if alive {
                if kept != read_at - 1usize {
                    unsafe { core.ptr.`copy`(p.cast_const(), self.ptr.add(kept), 1usize) }
                }
                kept += 1usize
            } else {
                unsafe { core.ptr.drop_in_place(p) }
            }
        }
        self.len = kept
    }

    pub mut fn pop_if<F: fn(mut T): bool>(test: take F): T? {
        if self.len == 0usize { return none }
        let last = unsafe { self.ptr.add(self.len - 1usize) }
        if test(unsafe { mut *last }) { self.pop() } else { none }
    }

    pub mut fn extract_if<F: fn(mut T): bool>(
        start: usize,
        end: usize,
        test: take F
    ): ExtractIf<region self, T, A, F> {
        if start > end || end > self.len { panic_precondition() }
        ExtractIf(mut self, start, end - start, test)
    }

    pub mut fn splice<I: OwnedIterable<Item = T>>(
        start: usize,
        end: usize,
        replacement: take I
    ): Splice<region self, T, A, I.(OwnedIterable).IntoIter> where A: Clone {
        if start > end || end > self.len { panic_precondition() }
        var removed = new_in<T, A>(self.a.clone())
        {
            var drain = self.drain(start, end)
            while true {
                match take drain.next() {
                    present(value) => { removed.push(value) },
                    none => { break }
                }
            }
        }
        let source = replacement.into_iter()
        Splice(mut self, removed.into_iter(), source, start)
    }

    pub mut fn spare_capacity_mut(): mut [core.mem.MaybeUninit<T>] from self {
        let start = unsafe { self.ptr.add(self.len) }
        unsafe {
            mut *slice_ptr_mut(
                start.cast<core.mem.MaybeUninit<T>>(),
                self.cap - self.len
            )
        }
    }

    pub take fn leak(): mut [T] from static {
        let view = slice_ptr_mut(self.ptr, self.len)
        unsafe { core.mem.forget(take self) }
        unsafe { mut *view }
    }

    pub take fn into_boxed_slice(): super.boxed.Box<[T], A> {
        let size = core.mem.size_of<T>()
        let old_ptr = self.ptr
        let old_cap = self.cap
        let n = self.len
        var allocator = unsafe { core.ptr.`read`(core.ptr.from_ref(self.a)) }
        unsafe { core.mem.forget(take self) }
        var pointer = old_ptr
        if size != 0usize && old_cap != n {
            if n == 0usize {
                if old_cap != 0usize {
                    unsafe {
                        allocator.deallocate(
                            old_ptr.cast<u8>(),
                            layout_unchecked(old_cap * size, core.mem.align_of<T>())
                        )
                    }
                }
                pointer = dangling_for<T>()
            } else {
                let bytes = n * size
                let layout = unsafe { layout_unchecked(bytes, core.mem.align_of<T>()) }
                let new_ptr = match capture allocator.allocate(layout) {
                    success(p) => p.cast<T>(),
                    failure(_) => handle_alloc_error(layout)
                }
                var i = 0usize
                while i < n {
                    unsafe {
                        let value = core.ptr.`read`(old_ptr.add(i))
                        core.ptr.write(new_ptr.add(i), value)
                    }
                    i += 1usize
                }
                if old_cap != 0usize {
                    unsafe {
                        allocator.deallocate(
                            old_ptr.cast<u8>(),
                            layout_unchecked(old_cap * size, core.mem.align_of<T>())
                        )
                    }
                }
                pointer = new_ptr
            }
        }
        let slice = slice_ptr_mut(pointer, n)
        unsafe { super.boxed.from_raw_in(slice, allocator) }
    }
}

type DrainFinish<T, A: Allocator> {
    list: ptr<mut List<T, A>>
    start: usize
    tail_start: usize
    tail_len: usize
    drop {
        // Safety: the live exclusive drain loan keeps the list allocation
        // stable; its validated range bounds both source and destination.
        unsafe {
            let list = self.list
            if self.tail_len != 0usize {
                core.ptr.`copy`((*list).ptr.add(self.tail_start).cast_const(),
                                (*list).ptr.add(self.start), self.tail_len)
            }
            (*list).len = self.start + self.tail_len
        }
    }
}

// The tail remains excluded from the list until this iterator is dropped.
pub type Drain<region r, T, A: Allocator> {
    list: mut List<T, A> from r
    start: usize
    front: usize
    back: usize
    tail_start: usize
    tail_len: usize
    drop {
        let _finish = DrainFinish(core.ptr.from_mut(self.list), self.start,
                                  self.tail_start, self.tail_len)
        drop_run(unsafe { self.list.ptr.add(self.front) }, self.back - self.front)
    }
}

pub type ExtractIf<region r, T, A: Allocator, F> {
    list: mut List<T, A> from r
    index: usize
    remaining: usize
    test: F
}
extend<region r, T, A: Allocator, F: fn(mut T): bool> ExtractIf<region r, T, A, F> implements Iterator {
    type Item = T
    mut fn next(): T? {
        while self.remaining > 0usize {
            self.remaining -= 1usize
            let remove = match take self.list.get_mut(self.index) {
                present(value) => self.test(mut *value),
                none => { return none }
            }
            if remove { return present(self.list.remove(self.index)) }
            self.index += 1usize
        }
        none
    }
}

extend<region r, T, A: Allocator> Drain<region r, T, A> {
    // The unyielded drained elements stay initialized between front and back.
    pub fn as_slice(): read [T] from self {
        unsafe { read *slice_ptr(self.list.ptr.add(self.front), self.back - self.front) }
    }
}

extend<region r, T, A: Allocator> Drain<region r, T, A> implements Iterator {
    type Item = T
    mut fn next(): T? {
        if self.front == self.back { return none }
        let index = self.front
        self.front += 1usize
        present(unsafe { core.ptr.`read`(self.list.ptr.add(index)) })
    }
}

extend<region r, T, A: Allocator> Drain<region r, T, A> implements BidirectionalIterator {
    mut fn next_back(): T? {
        if self.front == self.back { return none }
        self.back -= 1usize
        present(unsafe { core.ptr.`read`(self.list.ptr.add(self.back)) })
    }
}

extend<T: Clone, A: Allocator> List<T, A> {
    pub mut fn extend_from_slice(items: read [T]): Unit {
        self.reserve(items.len())
        var i = 0usize
        while i < items.len() {
            self.push(items[i].clone())
            i += 1usize
        }
    }
    pub mut fn extend_from_within(start: usize, end: usize): Unit {
        let old_len = self.len
        if start > end || end > old_len { panic_precondition() }
        let count = end - start
        self.reserve(count)
        var i = 0usize
        while i < count {
            let value = unsafe { read *self.ptr.add(start + i) }.clone()
            self.push(value)
            i += 1usize
        }
    }
    pub mut fn resize(n: usize, value: read T): Unit {
        if n <= self.len { self.truncate(n); return () }
        self.reserve(n - self.len)
        while self.len < n { self.push(value.clone()) }
    }
    pub mut fn resize_with<F: fn(): T>(n: usize, generate: take F): Unit {
        if n <= self.len { self.truncate(n); return () }
        self.reserve(n - self.len)
        while self.len < n { self.push(generate()) }
    }
}

extend<T: Clone> [T] {
    pub fn to_vec(): List<T> {
        var result = with_capacity<T>(self.len())
        result.extend_from_slice(self)
        result
    }
    pub fn repeat(times: usize): List<T> {
        let total = match self.len().checked_mul(times) {
            present(n) => n,
            none => { handle_alloc_error(layout_of<T>()) }
        }
        var result = with_capacity<T>(total)
        var repetition = 0usize
        while repetition < times {
            result.extend_from_slice(self)
            repetition += 1usize
        }
        result
    }
}

extend<T: PartialEq, A: Allocator> List<T, A> {
    pub fn contains(x: read T): bool {
        var i = 0usize
        while i < self.len {
            if unsafe { read *self.ptr.add(i) } == x { return true }
            i += 1usize
        }
        false
    }
    // Removes consecutive duplicates.
    pub mut fn dedup(): Unit {
        if self.len < 2usize { return () }
        let n = self.len
        self.len = 1usize
        var read_at = 1usize
        var kept = 1usize
        while read_at < n {
            let p = unsafe { self.ptr.add(read_at) }
            let same = unsafe { read *p } == unsafe { read *self.ptr.add(kept - 1usize) }
            read_at += 1usize
            if same {
                unsafe { core.ptr.drop_in_place(p) }
            } else {
                if kept != read_at - 1usize { unsafe { core.ptr.`copy`(p.cast_const(), self.ptr.add(kept), 1usize) } }
                kept += 1usize
            }
        }
        self.len = kept
    }
}

extend<T, A: Allocator> List<T, A> {
    pub mut fn dedup_by<F: fn(mut T, mut T): bool>(same: take F): Unit {
        if self.len < 2usize { return () }
        let n = self.len
        self.len = 1usize
        var read_at = 1usize
        var kept = 1usize
        while read_at < n {
            let current = unsafe { self.ptr.add(read_at) }
            let previous = unsafe { self.ptr.add(kept - 1usize) }
            let duplicate = same(unsafe { mut *current }, unsafe { mut *previous })
            read_at += 1usize
            if duplicate {
                unsafe { core.ptr.drop_in_place(current) }
            } else {
                if kept != read_at - 1usize {
                    unsafe { core.ptr.`copy`(current.cast_const(), self.ptr.add(kept), 1usize) }
                }
                kept += 1usize
            }
        }
        self.len = kept
    }

    pub mut fn dedup_by_key<K: PartialEq, F: fn(mut T): K>(key: take F): Unit {
        if self.len < 2usize { return () }
        let n = self.len
        self.len = 1usize
        var read_at = 1usize
        var kept = 1usize
        while read_at < n {
            let current = unsafe { self.ptr.add(read_at) }
            let previous = unsafe { self.ptr.add(kept - 1usize) }
            let current_key = key(unsafe { mut *current })
            let previous_key = key(unsafe { mut *previous })
            let duplicate = current_key == previous_key
            read_at += 1usize
            if duplicate {
                unsafe { core.ptr.drop_in_place(current) }
            } else {
                if kept != read_at - 1usize {
                    unsafe { core.ptr.`copy`(current.cast_const(), self.ptr.add(kept), 1usize) }
                }
                kept += 1usize
            }
        }
        self.len = kept
    }
}

// Sort indices first, then apply their permutation with swaps. Comparisons
// never observe a moved-from slot, even if they panic.
pub fn stable_sort_by<T, F: fn(read T, read T): Ordering>(items: mut [T], compare: take F): Unit {
    let n = items.len()
    if n < 2usize { return () }
    var order = with_capacity<usize>(n)
    var scratch = with_capacity<usize>(n)
    var i = 0usize
    while i < n {
        order.push(i + 0usize)
        scratch.push(0usize)
        i += 1usize
    }
    var width = 1usize
    while width < n {
        var start = 0usize
        while start < n {
            let mid = if n - start < width { n } else { start + width }
            let end = if n - mid < width { n } else { mid + width }
            var left = start
            var right = mid
            var out = start
            while left < mid && right < end {
                let l = order[left]
                let r = order[right]
                if compare(read items[r], read items[l]).is_lt() {
                    scratch[out] = r
                    right += 1usize
                } else {
                    scratch[out] = l
                    left += 1usize
                }
                out += 1usize
            }
            while left < mid {
                scratch[out] = order[left]
                left += 1usize
                out += 1usize
            }
            while right < end {
                scratch[out] = order[right]
                right += 1usize
                out += 1usize
            }
            start = end
        }
        i = 0usize
        while i < n { order[i] = scratch[i]; i += 1usize }
        if width >= n - width { break }
        width += width
    }
    // `order[destination]` names the original element; invert it before
    // swapping so each entry follows the element currently in that slot.
    i = 0usize
    while i < n { scratch[order[i]] = i; i += 1usize }
    i = 0usize
    while i < n {
        while scratch[i] != i {
            let destination = scratch[i]
            items.swap(i, destination)
            scratch.swap(i, destination)
        }
        i += 1usize
    }
}

extend<T: Ord, A: Allocator> List<T, A> {
    pub mut fn sort(): Unit {
        stable_sort_by(self.as_mut_slice(), fn(a: read T, b: read T): Ordering { a.cmp(b) })
    }
}

extend<T, A: Allocator> List<T, A> {
    pub mut fn sort_by<F: fn(read T, read T): Ordering>(compare: take F): Unit {
        stable_sort_by(self.as_mut_slice(), take compare)
    }
    pub mut fn sort_by_key<K: Ord, F: fn(read T): K>(key: take F): Unit {
        self.sort_by(fn(a: read T, b: read T): Ordering {
            let left = key(a)
            let right = key(b)
            left.cmp(read right)
        })
    }
}

extend<T: Ord> [T] {
    pub mut fn sort(): Unit {
        stable_sort_by(mut self, fn(a: read T, b: read T): Ordering { a.cmp(b) })
    }
}

extend<T> [T] {
    pub mut fn sort_by<F: fn(read T, read T): Ordering>(compare: take F): Unit {
        stable_sort_by(mut self, take compare)
    }
    pub mut fn sort_by_key<K: Ord, F: fn(read T): K>(key: take F): Unit {
        self.sort_by(fn(a: read T, b: read T): Ordering {
            let left = key(a)
            let right = key(b)
            left.cmp(read right)
        })
    }
}

extend<T> [T] {
    pub mut fn sort_by_cached_key<K: Ord, F: fn(read T): K>(key: take F): Unit {
        let n = self.len()
        if n < 2usize { return () }
        var order = with_capacity<(K, usize)>(n)
        var i = 0usize
        while i < n {
            order.push((key(read self[i]), i))
            i += 1usize
        }
        order.sort_by(fn(a: read (K, usize), b: read (K, usize)): Ordering {
            a.0.cmp(read b.0)
        })
        var destination = with_capacity<usize>(n)
        i = 0usize
        while i < n { destination.push(0usize); i += 1usize }
        i = 0usize
        while i < n {
            destination[order[i].1] = i
            i += 1usize
        }
        i = 0usize
        while i < n {
            while destination[i] != i {
                let target = destination[i]
                self.swap(i, target)
                destination.swap(i, target)
            }
            i += 1usize
        }
    }
}

extend<T, A: Allocator + Default> List<T, A> implements Default {
    static fn default(): List<T, A> { new_in<T, A>(A.(Default).default()) }
}

extend<T: Clone, A: Allocator + Clone> List<T, A> implements Clone {
    fn clone(): List<T, A> {
        var out = with_capacity_in<T, A>(self.len, self.a.clone())
        var i = 0usize
        while i < self.len {
            out.push(unsafe { read *self.ptr.add(i) }.clone())
            i += 1usize
        }
        out
    }
}

extend<T, A: Allocator> List<T, A> implements package.core.ops.Index<usize> {
    type Output = T
    fn index(i: read usize): read T from self {
        if i >= self.len { panic_precondition() }
        unsafe { read *self.ptr.add(i) }
    }
}
extend<T, A: Allocator> List<T, A> implements package.core.ops.IndexMut<usize> {
    type Output = T
    mut fn index_mut(i: read usize): mut T from self {
        if i >= self.len { panic_precondition() }
        unsafe { mut *self.ptr.add(i) }
    }
}

extend<T, A: Allocator> List<T, A> implements Deref {
    type Target = [T]
    fn deref(): read [T] from self { self.as_slice() }
}
extend<T, A: Allocator> List<T, A> implements DerefMut {
    type Target = [T]
    mut fn deref_mut(): mut [T] from self { self.as_mut_slice() }
}
extend<T, A: Allocator> List<T, A> implements IndexRange {
    type Output = [T]
    fn index_range(start: usize, end: usize): read [T] from self {
        let stop = if end == 0xffffffffffffffffusize { self.len } else { end }
        if start > stop || stop > self.len { panic_precondition() }
        unsafe { read *slice_ptr(self.ptr.add(start), stop - start) }
    }
}
extend<T, A: Allocator> List<T, A> implements IndexRangeMut {
    type Output = [T]
    mut fn index_range_mut(start: usize, end: usize): mut [T] from self {
        let stop = if end == 0xffffffffffffffffusize { self.len } else { end }
        if start > stop || stop > self.len { panic_precondition() }
        unsafe { mut *slice_ptr_mut(self.ptr.add(start), stop - start) }
    }
}

extend<T: PartialEq, A: Allocator> List<T, A> implements PartialEq {
    fn eq(other: read List<T, A>): bool { self.as_slice() == other.as_slice() }
}
extend<T: Eq, A: Allocator> List<T, A> implements Eq {}
extend<T: PartialOrd, A: Allocator> List<T, A> implements PartialOrd {
    fn partial_cmp(other: read List<T, A>): Ordering? { self.as_slice().partial_cmp(other.as_slice()) }
}
extend<T: Ord, A: Allocator> List<T, A> implements Ord {
    fn cmp(other: read List<T, A>): Ordering { self.as_slice().cmp(other.as_slice()) }
}
// Hashes exactly like the slice view, so `List<T>` and `[T]` agree.
extend<T: Hash, A: Allocator> List<T, A> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.as_slice().hash(mut state) }
}
// By-value iterator; remaining elements and the buffer are released on drop.
pub type IntoIter<T, A: Allocator = Global> {
    buf: ptr<mut T>
    cap: usize
    front: usize
    back: usize
    a: A
    drop {
        let rest = self.back - self.front
        let p = unsafe { self.buf.add(self.front) }
        self.front = self.back
        let layout = unsafe { layout_unchecked(self.cap * core.mem.size_of<T>(), core.mem.align_of<T>()) }
        let _free = unsafe { free_block(self.buf.cast<u8>(), layout, core.ptr.from_mut(self.a)) }
        let _run = DropRun(p, rest)
    }
}

extend<T, A: Allocator> List<T, A> implements OwnedIterable {
    type Item = T
    type IntoIter = IntoIter<T, A>
    fn into_iter(receiver self: take Self): IntoIter<T, A> {
        unsafe {
            let buf = self.ptr
            let cap = self.cap
            let n = self.len
            let a = core.ptr.`read`(core.ptr.from_ref(self.a))
            core.mem.forget(take self)
            IntoIter(buf, cap, 0usize, n, a)
        }
    }
}

extend<T, A: Allocator> IntoIter<T, A> implements Iterator {
    type Item = T
    mut fn next(): T? {
        if self.front == self.back { return none }
        let i = self.front
        self.front += 1usize
        present(unsafe { core.ptr.`read`(self.buf.add(i)) })
    }
}
extend<T, A: Allocator> IntoIter<T, A> implements BidirectionalIterator {
    mut fn next_back(): T? {
        if self.front == self.back { return none }
        self.back -= 1usize
        present(unsafe { core.ptr.`read`(self.buf.add(self.back)) })
    }
}
pub type Splice<region r, T, A: Allocator, I: Iterator<Item = T>> {
    list: mut List<T, A> from r
    removed: IntoIter<T, A>
    replacement: I
    at: usize
    drop {
        while true {
            match take self.replacement.next() {
                present(value) => {
                    self.list.insert(self.at, value)
                    self.at += 1usize
                },
                none => { break }
            }
        }
    }
}
extend<region r, T, A: Allocator, I: Iterator<Item = T>> Splice<region r, T, A, I> implements Iterator {
    type Item = T
    mut fn next(): T? { self.removed.next() }
}
extend<region r, T, A: Allocator, I: Iterator<Item = T>> Splice<region r, T, A, I> implements BidirectionalIterator {
    mut fn next_back(): T? { self.removed.next_back() }
}
extend<T, A: Allocator> IntoIter<T, A> {
    pub fn len(): usize { self.back - self.front }
}

// Borrowed iteration: `for x in read v` yields `read T from v`, `for x in mut v`
// yields `mut T from v`; the loop keeps the vector borrowed.
extend<T, A: Allocator> List<T, A> implements Iterable {
    type Item = T
    type Iter<region r> = SliceIter<region r, T>
    fn iter<region r>(receiver self: read Self from r): SliceIter<region r, T> { self.as_slice().iter() }
}
extend<T, A: Allocator> List<T, A> implements MutableIterable {
    type Item = T
    type IterMut<region r> = SliceIterMut<region r, T>
    fn iter_mut<region r>(receiver self: mut Self from r): SliceIterMut<region r, T> { self.as_mut_slice().iter_mut() }
}

extend<T, A: Allocator> List<T, A> implements ExtendItems<T> {
    mut fn extend<I: OwnedIterable<Item = T>>(items: take I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { self.push(item) }, none => { break } }
        }
    }
}
extend<T> List<T> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(items: take I): List<T> {
        var out = new<T>()
        out.extend(items)
        out
    }
}

extend<T: fmt.Debug, A: Allocator> List<T, A> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try fmt.debug_slice(self.as_slice(), mut f)
    }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<T: Transferable, A: Allocator + Transferable> List<T, A> implements Transferable {}
unsafe extend<T: Shareable, A: Allocator + Shareable> List<T, A> implements Shareable {}
