import super.alloc.{ Allocator, Global, AllocError, Layout, layout_of, layout_unchecked, free_block, handle_alloc_error, panic_precondition, dangling_for }
import package.core.clone.Clone
import package.core.default.Default
import package.core.cmp.{ Eq, Ord, Ordering, PartialEq, PartialOrd }
import package.core.hash.{ Hash, Hasher }
import package.core.fmt
import package.core.ops.{ Deref, DerefMut, IndexRange, IndexRangeMut, RangeEnd }
import package.core.iter.{ Iterator, BidirectionalIterator, ExactSizeIterator, FusedIterator, Bound, RangeBounds, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems }
import package.core.slice.{ SliceIter, SliceIterMut }
import package.core.text.Text
import package.core.borrow.{ AsMut, AsRef, Borrow, BorrowMut }
import package.core.convert.{From, TryFrom}
import package.core.ptr.NonNull

copy type RawSlice<T> { data: ptr<read T>; len: usize }

fn normalize_range<R: RangeBounds<usize>>(
    take range: R,
    len: usize
): (usize, usize) {
    let start = match R.(RangeBounds<usize>).start_bound(read range) {
        Bound.Included(value) => *value,
        Bound.Excluded(value) => match (*value).checked_add(1usize) {
            present(index) => index,
            none => panic_precondition()
        },
        Bound.Unbounded => 0usize
    }
    let end = match R.(RangeBounds<usize>).end_bound(read range) {
        Bound.Excluded(value) => *value,
        Bound.Included(value) => match (*value).checked_add(1usize) {
            present(index) => index,
            none => panic_precondition()
        },
        Bound.Unbounded => len
    }
    if start > end || end > len { panic_precondition() }
    (start, end)
}

// Slice pointers carry no region; callers turn them into views anchored to
// the owner's own storage.
pub const fn slice_ptr<T>(p: ptr<mut T>, n: usize): ptr<read [T]> {
    let raw = RawSlice(p.cast_const(), n)
    unsafe { core.mem.transmute<ptr<read [T]>>(raw) }
}
pub const fn slice_ptr_mut<T>(p: ptr<mut T>, n: usize): ptr<mut [T]> {
    let raw = RawSlice(p.cast_const(), n)
    unsafe { core.mem.transmute<ptr<mut [T]>>(raw) }
}

// Drops `n` consecutive values. If one destructor panics the guard's own
// destructor still drops the rest.
type DropRun<T> {
    p: ptr<mut T>
    n: usize
    drop { self.run() }
}

extend<T> DropRun<T> {
    mut const fn run(): Unit {
        while self.n != 0usize {
            let current = self.p
            self.p = unsafe { self.p.add(1usize) }
            self.n -= 1usize
            unsafe { core.ptr.drop_in_place(current) }
        }
    }
}

// Safety: p owns n initialized aligned elements exclusively; the extent remains live through cleanup.
pub unsafe fn drop_run<T>(p: ptr<mut T>, n: usize): Unit {
    var guard = DropRun(p, n)
    guard.run()
}

// Invariant: `ptr` is non-null even when the list is empty; `init` uses
// `dangling_for<T>()`, and raw-parts construction requires a non-null pointer.
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
        var run = DropRun(self.ptr, n)
        run.run()
    }
}

pub const fn new_in<T, A: Allocator>(take a: A): List<T, A> {
    let result: List<T, A>
    result.ptr = dangling_for<T>()
    result.len = 0usize
    result.cap = if core.mem.size_of<T>() == 0usize { 0xffffffffffffffffusize } else { 0usize }
    result.a = take a
    result
}
pub const fn new<T>(): List<T> { new_in(Global()) }

pub fn from_array<T, const N: usize>(take items: [T; N]): List<T> {
    List<T>.(From<[T; N]>).from(items)
}

pub fn from_elem<T: Clone>(take value: T, count: usize): List<T> {
    var out = with_capacity<T>(count)
    if count == 0usize { return out }
    var i = 1usize
    while i < count {
        out.push(value.clone())
        i += 1usize
    }
    out.push(value)
    out
}

pub macro vec {
    () => { new() };
    ($value:expr; $count:expr) => { from_elem($value, $count) };
    ($($value:expr),+ $(,)?) => { from_array([$($value),*]) };
}

pub fn try_with_capacity_in<T, A: Allocator>(n: usize, take a: A): List<T, A> throws AllocError {
    var v = new_in<T, A>(a)
    try v.try_reserve_exact(n)
    v
}
pub fn with_capacity_in<T, A: Allocator>(n: usize, take a: A): List<T, A> {
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
    pub init(take allocator: A) {
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

    pub const fn as_slice(): read [T] from self { unsafe { read *slice_ptr(self.ptr, self.len) } }
    pub mut const fn as_mut_slice(): mut [T] from self { unsafe { mut *slice_ptr_mut(self.ptr, self.len) } }

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
            unsafe { try self.a.grow(self.ptr.cast<u8>(), layout_unchecked(self.cap * size, align), bytes) }
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
        let outcome = unsafe { capture self.a.shrink(self.ptr.cast<u8>(), old, target * size) }
        match take outcome {
            success(np) => {
                self.ptr = np.cast<T>()
                self.cap = target
            },
            failure(_) => ()
        }
    }

    // On allocation failure the error retains the value and the vector is unchanged.
    pub mut fn try_push(take value: T): Unit throws super.alloc.PushError<T> {
        match capture self.try_reserve(1usize) {
            success(_) => {},
            failure(error) => { throw super.alloc.PushError(value, error) }
        }
        unsafe { core.ptr.write(self.ptr.add(self.len), value) }
        self.len += 1usize
    }
    pub mut fn push(take value: T): Unit {
        if self.len == self.cap { self.reserve(1usize) }
        unsafe { core.ptr.write(self.ptr.add(self.len), value) }
        self.len += 1usize
    }
    pub mut fn push_mut(take value: T): mut T from self {
        self.push(value)
        self.get_mut(self.len - 1usize).unwrap()
    }
    pub mut fn pop(): T? {
        if self.len == 0usize { return none }
        self.len -= 1usize
        present(unsafe { core.ptr.`read`(self.ptr.add(self.len)) })
    }
    pub mut fn insert(index: usize, take value: T): Unit {
        if index > self.len { panic_precondition() }
        if self.len == self.cap { self.reserve(1usize) }
        unsafe {
            let p = self.ptr.add(index)
            core.ptr.`copy`(p.cast_const(), p.add(1usize), self.len - index)
            core.ptr.write(p, value)
        }
        self.len += 1usize
    }
    pub mut fn insert_mut(index: usize, take value: T): mut T from self {
        self.insert(index, value)
        self.get_mut(index).unwrap()
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
        unsafe { drop_run(self.ptr.add(n), old - n) }
    }
    pub mut fn clear(): Unit { self.truncate(0usize) }

    pub mut fn drain<R: RangeBounds<usize>>(
        take range: R
    ): Drain<region self, T, A> {
        let (start, end) = normalize_range(take range, self.len)
        self.drain_bounds(start, end)
    }

    mut fn drain_bounds(start: usize, end: usize): Drain<region self, T, A> {
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
    pub mut fn append(mut other: List<T, A>): Unit {
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

    // Both retain variants visit once in order, without allocating. The guard
    // restores kept and unvisited elements if a predicate or destructor panics.
    pub mut fn retain<F: mut fn(read T): bool>(take keep: F): Unit {
        var predicate = take keep
        let n = self.len
        self.len = 0usize
        var guard = RetainGuard(core.ptr.from_mut(self), n, 0usize, 0usize)
        while guard.processed < n {
            let p = unsafe { self.ptr.add(guard.processed) }
            let alive = predicate(unsafe { read *p })
            if alive {
                if guard.deleted != 0usize {
                    unsafe { core.ptr.`copy`(p.cast_const(), self.ptr.add(guard.processed - guard.deleted), 1usize) }
                }
                guard.processed += 1usize
            } else {
                guard.processed += 1usize
                guard.deleted += 1usize
                unsafe { core.ptr.drop_in_place(p) }
            }
        }
    }

    pub mut fn retain_mut<F: mut fn(mut T): bool>(take keep: F): Unit {
        var predicate = take keep
        let n = self.len
        self.len = 0usize
        var guard = RetainGuard(core.ptr.from_mut(self), n, 0usize, 0usize)
        while guard.processed < n {
            let p = unsafe { self.ptr.add(guard.processed) }
            let alive = predicate(unsafe { mut *p })
            if alive {
                if guard.deleted != 0usize {
                    unsafe { core.ptr.`copy`(p.cast_const(), self.ptr.add(guard.processed - guard.deleted), 1usize) }
                }
                guard.processed += 1usize
            } else {
                guard.processed += 1usize
                guard.deleted += 1usize
                unsafe { core.ptr.drop_in_place(p) }
            }
        }
    }

    pub mut fn pop_if<F: take fn(mut T): bool>(take test: F): T? {
        if self.len == 0usize { return none }
        let last = unsafe { self.ptr.add(self.len - 1usize) }
        if test(unsafe { mut *last }) { self.pop() } else { none }
    }

    pub mut fn extract_if<R: RangeBounds<usize>, F: mut fn(mut T): bool>(
        take range: R,
        take test: F
    ): ExtractIf<region self, T, A, F> {
        let (start, end) = normalize_range(take range, self.len)
        let original_len = self.len
        self.len = start
        ExtractIf(mut self, original_len, start, end, 0usize, false, test)
    }

    pub mut fn splice<R: RangeBounds<usize>, I: OwnedIterable<Item = T>>(
        take range: R,
        take replacement: I
    ): Splice<region self, T, A, I.(OwnedIterable).IntoIter> where A: Clone {
        let (start, end) = normalize_range(take range, self.len)
        var removed = new_in<T, A>(self.a.clone())
        {
            var drain = self.drain_bounds(start, end)
            while true {
                match take drain.next() {
                    present(value) => { removed.push(value) },
                    none => { break }
                }
            }
        }
        let pending = new_in<T, A>(self.a.clone())
        let source = replacement.into_iter()
        Splice(mut self, removed.into_iter(), source, pending, start)
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

type RetainGuard<T, A: Allocator> {
    list: ptr<mut List<T, A>>
    original_len: usize
    processed: usize
    deleted: usize
    drop {
        // The exclusive receiver keeps allocation/layout stable. Initialized
        // values occupy [0, processed - deleted) and [processed, original_len).
        // Skip a removed value before dropping it, including on unwind.
        unsafe {
            let list = self.list
            if self.deleted != 0usize && self.processed != self.original_len {
                core.ptr.`copy`((*list).ptr.add(self.processed).cast_const(),
                    (*list).ptr.add(self.processed - self.deleted),
                    self.original_len - self.processed)
            }
            (*list).len = self.original_len - self.deleted
        }
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
        unsafe { drop_run(self.list.ptr.add(self.front), self.back - self.front) }
    }
}

// Safety: owned slots are [0, index-deleted) and [index, original_len); the gap owns nothing.
pub type ExtractIf<region r, T, A: Allocator, F> {
    list: mut List<T, A> from r
    original_len: usize
    index: usize
    end: usize
    deleted: usize
    panicked: bool
    test: F
    drop {
        unsafe {
            if self.deleted != 0usize {
                core.ptr.`copy`(
                    self.list.ptr.add(self.index).cast_const(),
                    self.list.ptr.add(self.index - self.deleted),
                    self.original_len - self.index
                )
            }
            self.list.len = self.original_len - self.deleted
        }
    }
}
extend<region r, T, A: Allocator, F: mut fn(mut T): bool> ExtractIf<region r, T, A, F> implements Iterator {
    type Item = T
    fn size_hint(): (usize, usize?) {
        (0usize, present(if self.panicked { 0usize } else { self.end - self.index }))
    }
    mut fn next(): T? {
        if self.panicked { return none }
        while self.index < self.end {
            let current = unsafe { self.list.ptr.add(self.index) }
            self.panicked = true
            let remove = self.test(unsafe { mut *current })
            self.panicked = false
            self.index += 1usize
            if remove {
                self.deleted += 1usize
                return present(unsafe { core.ptr.`read`(current) })
            }
            if self.deleted != 0usize {
                unsafe {
                    core.ptr.`copy`(
                        current.cast_const(),
                        self.list.ptr.add(self.index - self.deleted - 1usize),
                        1usize
                    )
                }
            }
        }
        none
    }
}
extend<region r, T, A: Allocator, F: mut fn(mut T): bool> ExtractIf<region r, T, A, F> implements FusedIterator {}

extend<region r, T, A: Allocator> Drain<region r, T, A> {
    // The unyielded drained elements stay initialized between front and back.
    pub fn as_slice(): read [T] from self {
        unsafe { read *slice_ptr(self.list.ptr.add(self.front), self.back - self.front) }
    }
}

extend<region r, T, A: Allocator> Drain<region r, T, A> implements Iterator {
    type Item = T
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.front
        (remaining, present(remaining))
    }
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
extend<region r, T, A: Allocator> Drain<region r, T, A> implements ExactSizeIterator {}
extend<region r, T, A: Allocator> Drain<region r, T, A> implements FusedIterator {}
extend<region r, T, A: Allocator> Drain<region r, T, A> implements AsRef<[T]> {
    fn as_ref(): read [T] from self { self.as_slice() }
}
extend<region r, T: fmt.Debug, A: Allocator> Drain<region r, T, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("Drain(")
        try fmt.debug_slice(self.as_slice(), mut f)
        try f.write_str(")")
    }
}

extend<T: Clone, A: Allocator> List<T, A> {
    pub mut fn extend_from_slice(read items: [T]): Unit {
        self.reserve(items.len())
        var i = 0usize
        while i < items.len() {
            self.push(items[i].clone())
            i += 1usize
        }
    }
    pub mut fn extend_from_within<R: RangeBounds<usize>>(take range: R): Unit {
        let old_len = self.len
        let (start, end) = normalize_range(take range, old_len)
        let count = end - start
        self.reserve(count)
        var i = 0usize
        while i < count {
            let value = unsafe { read *self.ptr.add(start + i) }.clone()
            self.push(value)
            i += 1usize
        }
    }
    pub mut fn resize(n: usize, read value: T): Unit {
        if n <= self.len { self.truncate(n); return () }
        self.reserve(n - self.len)
        while self.len < n { self.push(value.clone()) }
    }
}

extend<T, A: Allocator> List<T, A> {
    pub mut fn resize_with<F: mut fn(): T>(n: usize, take generate: F): Unit {
        if n <= self.len { self.truncate(n); return () }
        self.reserve(n - self.len)
        var generator = take generate
        while self.len < n { self.push(generator()) }
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
    pub fn contains(read x: T): bool {
        var i = 0usize
        while i < self.len {
            if unsafe { read *self.ptr.add(i) } == x { return true }
            i += 1usize
        }
        false
    }
    // Removes consecutive duplicates.
    pub mut fn dedup(): Unit {
        self.dedup_by(fn(mut current: T, mut previous: T): bool {
            current.eq(read previous)
        })
    }
}

extend<V> [V] {
    pub fn concat<T: Clone>(): List<T> where V: Borrow<[T]> {
        var result = with_capacity<T>(0usize)
        for part in read self { result.extend_from_slice(V.(Borrow<[T]>).borrow(part)) }
        result
    }
    pub fn join<T: Clone>(read sep: [T]): List<T> where V: Borrow<[T]> {
        var result = with_capacity<T>(0usize)
        var first = true
        for part in read self {
            if !first { result.extend_from_slice(sep) }
            first = false
            result.extend_from_slice(V.(Borrow<[T]>).borrow(part))
        }
        result
    }
}

extend [u8] {
pub fn to_ascii_lowercase(): List<u8> {
        var result = with_capacity<u8>(self.len())
        result.extend_from_slice(self)
        result.as_mut_slice().make_ascii_lowercase()
        result
    }

    pub fn to_ascii_uppercase(): List<u8> {
        var result = with_capacity<u8>(self.len())
        result.extend_from_slice(self)
        result.as_mut_slice().make_ascii_uppercase()
        result
    }
}

extend<T, A: Allocator> List<T, A> {
    pub mut fn dedup_by<F: mut fn(mut T, mut T): bool>(take same: F): Unit {
        if self.len < 2usize { return () }
        var predicate = take same
        let n = self.len
        self.len = 0usize
        var guard = RetainGuard(core.ptr.from_mut(self), n, 1usize, 0usize)
        while guard.processed < n {
            let current = unsafe { self.ptr.add(guard.processed) }
            let previous = unsafe { self.ptr.add(guard.processed - guard.deleted - 1usize) }
            let duplicate = predicate(unsafe { mut *current }, unsafe { mut *previous })
            if duplicate {
                guard.processed += 1usize
                guard.deleted += 1usize
                unsafe { core.ptr.drop_in_place(current) }
            } else {
                if guard.deleted != 0usize {
                    unsafe {
                        core.ptr.`copy`(
                            current.cast_const(),
                            self.ptr.add(guard.processed - guard.deleted),
                            1usize
                        )
                    }
                }
                guard.processed += 1usize
            }
        }
    }

    pub mut fn dedup_by_key<K: PartialEq, F: mut fn(mut T): K>(take key: F): Unit {
        if self.len < 2usize { return () }
        var project = take key
        let n = self.len
        self.len = 0usize
        var guard = RetainGuard(core.ptr.from_mut(self), n, 1usize, 0usize)
        while guard.processed < n {
            let current = unsafe { self.ptr.add(guard.processed) }
            let previous = unsafe { self.ptr.add(guard.processed - guard.deleted - 1usize) }
            let current_key = project(unsafe { mut *current })
            let previous_key = project(unsafe { mut *previous })
            let duplicate = current_key == previous_key
            if duplicate {
                guard.processed += 1usize
                guard.deleted += 1usize
                unsafe { core.ptr.drop_in_place(current) }
            } else {
                if guard.deleted != 0usize {
                    unsafe {
                        core.ptr.`copy`(
                            current.cast_const(),
                            self.ptr.add(guard.processed - guard.deleted),
                            1usize
                        )
                    }
                }
                guard.processed += 1usize
            }
        }
    }
}

// Sort indices first, then apply their permutation with swaps. Comparisons
// never observe a moved-from slot, even if they panic.
pub fn stable_sort_by<T, F: mut fn(read T, read T): Ordering>(mut items: [T], take compare: F): Unit {
    let n = items.len()
    if n < 2usize { return () }
    var comparator = take compare
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
                if comparator(read items[r], read items[l]).is_lt() {
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
        stable_sort_by(self.as_mut_slice(), fn(read a: T, read b: T): Ordering { a.cmp(b) })
    }
}

extend<T, A: Allocator> List<T, A> {
    pub mut fn sort_by<F: mut fn(read T, read T): Ordering>(take compare: F): Unit {
        stable_sort_by(self.as_mut_slice(), take compare)
    }
    pub mut fn sort_by_key<K: Ord, F: mut fn(read T): K>(take key: F): Unit {
        var project = take key
        self.sort_by(fn(read a: T, read b: T): Ordering {
            let left = project(a)
            let right = project(b)
            left.cmp(read right)
        })
    }
}

extend<T: Ord> [T] {
    pub mut fn sort(): Unit {
        stable_sort_by(mut self, fn(read a: T, read b: T): Ordering { a.cmp(b) })
    }
}

extend<T> [T] {
    pub mut fn sort_by<F: mut fn(read T, read T): Ordering>(take compare: F): Unit {
        stable_sort_by(mut self, take compare)
    }
    pub mut fn sort_by_key<K: Ord, F: mut fn(read T): K>(take key: F): Unit {
        var project = take key
        self.sort_by(fn(read a: T, read b: T): Ordering {
            let left = project(a)
            let right = project(b)
            left.cmp(read right)
        })
    }
}

extend<T> [T] {
    pub mut fn sort_by_cached_key<K: Ord, F: mut fn(read T): K>(take key: F): Unit {
        let n = self.len()
        if n < 2usize { return () }
        var project = take key
        var order = with_capacity<(K, usize)>(n)
        var i = 0usize
        while i < n {
            order.push((project(read self[i]), i))
            i += 1usize
        }
        order.sort_by(fn(read a: (K, usize), read b: (K, usize)): Ordering {
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

extend<T, const N: usize, A: Allocator> List<[T; N], A> {
    pub take fn into_flattened(): List<T, A> {
        let flat_len = match self.len.checked_mul(N) {
            present(n) => n,
            none => super.alloc.panic_precondition()
        }
        let flat_capacity = if core.mem.size_of<T>() == 0usize {
            0xffffffffffffffffusize
        } else {
            if N == 0usize {
                0usize
            } else {
                match self.cap.checked_mul(N) {
                    present(n) => n,
                    none => super.alloc.panic_precondition()
                }
            }
        }

        let pointer = self.ptr.cast<T>()
        // Safety: move the allocator out before forgetting the old owner.
        var allocator = unsafe {
            core.ptr.`read`(core.ptr.from_ref(self.a))
        }
        var flattened = new_in<T, A>(take allocator)
        flattened.ptr = pointer
        flattened.len = flat_len
        flattened.cap = flat_capacity
        // The output owns the same bytes: cap * size([T; N]) equals
        // flat_capacity * size(T), including the zero-sized cases above.
        unsafe { core.mem.forget(take self) }
        flattened
    }
}

extend<T> List<T> {
    // Safety: the pointer must be non-null and satisfy List's allocation,
    // alignment, initialization, length and capacity invariants for Global.
    pub unsafe static fn from_raw_parts(
        pointer: ptr<mut T>,
        length: usize,
        capacity: usize
    ): List<T> {
        var list = new<T>()
        list.ptr = pointer
        list.len = length
        list.cap = capacity
        list
    }

    pub take fn into_raw_parts(): (ptr<mut T>, usize, usize) {
        let pointer = self.ptr
        let length = self.len
        let capacity = self.cap
        unsafe { core.mem.forget(take self) }
        (pointer, length, capacity)
    }
}

extend<T, A: Allocator> List<T, A> {
    // Safety: the pointer must be non-null and satisfy List's allocation,
    // alignment, initialization, length and capacity invariants for allocator.
    pub unsafe static fn from_raw_parts_in(
        pointer: ptr<mut T>,
        length: usize,
        capacity: usize,
        take allocator: A
    ): List<T, A> {
        var list = new_in<T, A>(take allocator)
        list.ptr = pointer
        list.len = length
        list.cap = capacity
        list
    }

    pub take fn into_raw_parts_with_alloc(): (ptr<mut T>, usize, usize, A) {
        let pointer = self.ptr
        let length = self.len
        let capacity = self.cap
        let allocator = unsafe { core.ptr.`read`(core.ptr.from_ref(self.a)) }
        unsafe { core.mem.forget(take self) }
        (pointer, length, capacity, allocator)
    }

    // `NonNull` proves only non-nullness; allocation, alignment, length and
    // capacity remain the caller's safety obligations.
    pub unsafe static fn from_parts_in(
        pointer: NonNull<T>,
        length: usize,
        capacity: usize,
        take allocator: A
    ): List<T, A> {
        List<T, A>.from_raw_parts_in(
            pointer.as_ptr(),
            length,
            capacity,
            take allocator
        )
    }

    pub take fn into_parts_with_alloc(): (NonNull<T>, usize, usize, A) {
        let (pointer, length, capacity, allocator) =
            self.into_raw_parts_with_alloc()
        let pointer = unsafe { NonNull<T>.new_unchecked(pointer) }
        (pointer, length, capacity, allocator)
    }
}

extend<T> List<T> {
    pub unsafe static fn from_parts(
        pointer: NonNull<T>,
        length: usize,
        capacity: usize
    ): List<T> {
        List<T>.from_parts_in(pointer, length, capacity, Global())
    }

    pub take fn into_parts(): (NonNull<T>, usize, usize) {
        let (pointer, length, capacity) = self.into_raw_parts()
        let pointer = unsafe { NonNull<T>.new_unchecked(pointer) }
        (pointer, length, capacity)
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
    fn index(read i: usize): read T from self {
        if i >= self.len { panic_precondition() }
        unsafe { read *self.ptr.add(i) }
    }
}
extend<T, A: Allocator> List<T, A> implements package.core.ops.IndexMut<usize> {
    type Output = T
    mut fn index_mut(read i: usize): mut T from self {
        if i >= self.len { panic_precondition() }
        unsafe { mut *self.ptr.add(i) }
    }
}

extend<T, A: Allocator> List<T, A> implements Deref {
    type Target = [T]
    const fn deref(): read [T] from self { self.as_slice() }
}
extend<T, A: Allocator> List<T, A> implements DerefMut {
    mut const fn deref_mut(): mut [T] from self { self.as_mut_slice() }
}
fn range_index_end(end: RangeEnd, len: usize): usize {
    match end {
        RangeEnd.Unbounded => len,
        RangeEnd.Exclusive(value) => value,
        RangeEnd.Inclusive(value) => {
            if value >= len { panic_precondition() }
            value + 1usize
        }
    }
}

extend<T, A: Allocator> List<T, A> implements IndexRange {
    type Output = [T]
    fn index_range(start: usize, end: RangeEnd): read [T] from self {
        let stop = range_index_end(end, self.len)
        if start > stop || stop > self.len { panic_precondition() }
        unsafe { read *slice_ptr(self.ptr.add(start), stop - start) }
    }
}
extend<T, A: Allocator> List<T, A> implements IndexRangeMut {
    type Output = [T]
    mut fn index_range_mut(start: usize, end: RangeEnd): mut [T] from self {
        let stop = range_index_end(end, self.len)
        if start > stop || stop > self.len { panic_precondition() }
        unsafe { mut *slice_ptr_mut(self.ptr.add(start), stop - start) }
    }
}

extend<T, A: Allocator> List<T, A> implements AsRef<[T]> {
    fn as_ref(): read [T] from self { self.as_slice() }
}
extend<T, A: Allocator> List<T, A> implements AsMut<[T]> {
    mut fn as_mut(): mut [T] from self { self.as_mut_slice() }
}
extend<T, A: Allocator> List<T, A> implements Borrow<[T]> {
    fn borrow(): read [T] from self { self.as_slice() }
}
extend<T, A: Allocator> List<T, A> implements BorrowMut<[T]> {
    mut fn borrow_mut(): mut [T] from self { self.as_mut_slice() }
}

extend<T, const N: usize, A: Allocator> [T; N] implements TryFrom<List<T, A>> {
    type Error = List<T, A>
    static fn try_from(take value: List<T, A>): (Outcome<[T; N], List<T, A>>) {
        if value.len() != N { return failure(value) }
        var list = value
        let array = unsafe { core.ptr.`read`(list.as_ptr().cast<[T; N]>()) }
        unsafe { list.set_len(0usize) }
        success(array)
    }
}

// The boxed slice's allocation becomes the list's buffer; nothing is copied.
extend<T, A: Allocator> List<T, A> implements From<super.boxed.Box<[T], A>> {
    static fn from(take items: super.boxed.Box<[T], A>): List<T, A> {
        let length = items.get().len()
        let raw = items.into_raw()
        var list = new_in<T, A>(take raw.1)
        list.ptr = raw.0.cast<T>()
        list.len = length
        if core.mem.size_of<T>() != 0usize { list.cap = length }
        list
    }
}

// Moves the array's elements into a new exact-capacity list.
extend<T, const N: usize> List<T> implements From<[T; N]> {
    static fn from(take items: [T; N]): List<T> {
        var list = with_capacity<T>(N)
        unsafe {
            core.ptr.`copy`(core.ptr.from_ref(items).cast<T>(), list.ptr, N)
            core.mem.forget(take items)
        }
        list.len = N
        list
    }
}

extend<region r, T: Clone> List<T> implements From<read [T] from r> {
    static fn from(take items: read [T] from r): List<T> { items.to_vec() }
}
extend<region r, T: Clone> List<T> implements From<mut [T] from r> {
    static fn from(take items: mut [T] from r): List<T> { items.to_vec() }
}
extend<region r, T: Clone, const N: usize> List<T> implements From<read [T; N] from r> {
    static fn from(take items: read [T; N] from r): List<T> { items.to_vec() }
}
extend<region r, T: Clone, const N: usize> List<T> implements From<mut [T; N] from r> {
    static fn from(take items: mut [T; N] from r): List<T> { items.to_vec() }
}
extend<region r> List<u8> implements From<read Text from r> {
    static fn from(take text: read Text from r): List<u8> { text.as_bytes().to_vec() }
}
extend<T: PartialEq<U>, U, A: Allocator> List<T, A> implements PartialEq<[U]> {
    fn eq(read other: [U]): bool {
        if self.len != other.len() { return false }
        var i = 0usize
        while i < self.len {
            if unsafe { read *self.ptr.add(i) } != other[i] { return false }
            i += 1usize
        }
        true
    }
}

extend<T: PartialEq<U>, U, const N: usize, A: Allocator> List<T, A> implements PartialEq<[U; N]> {
    fn eq(read other: [U; N]): bool {
        if self.len != N { return false }
        var i = 0usize
        while i < N {
            if unsafe { read *self.ptr.add(i) } != other[i] { return false }
            i += 1usize
        }
        true
    }
}

extend<T: PartialEq<U>, U, A1: Allocator, A2: Allocator> List<T, A1> implements PartialEq<List<U, A2>> {
    fn eq(read other: List<U, A2>): bool {
        if self.len != other.len { return false }
        var i = 0usize
        while i < self.len {
            if unsafe { read *self.ptr.add(i) } != unsafe { read *other.ptr.add(i) } { return false }
            i += 1usize
        }
        true
    }
}
extend<T: Eq, A: Allocator> List<T, A> implements Eq {}
extend<T: PartialOrd, A1: Allocator, A2: Allocator> List<T, A1> implements PartialOrd<List<T, A2>> {
    fn partial_cmp(read other: List<T, A2>): Ordering? { self.as_slice().partial_cmp(other.as_slice()) }
}
extend<T: Ord, A: Allocator> List<T, A> implements Ord {
    fn cmp(read other: List<T, A>): Ordering { self.as_slice().cmp(other.as_slice()) }
}
// Hashes exactly like the slice view, so `List<T>` and `[T]` agree.
extend<T: Hash, A: Allocator> List<T, A> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.as_slice().hash(mut state) }
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
        var run = DropRun(p, rest)
        run.run()
    }
}

extend<T, A: Allocator> List<T, A> implements OwnedIterable {
    type Item = T
    type IntoIter = IntoIter<T, A>
    fn into_iter(receiver take self: Self): IntoIter<T, A> {
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
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.front
        (remaining, present(remaining))
    }
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
extend<T, A: Allocator> IntoIter<T, A> implements ExactSizeIterator {}
extend<T, A: Allocator> IntoIter<T, A> implements FusedIterator {}
pub type Splice<region r, T, A: Allocator, I: Iterator<Item = T>> {
    list: mut List<T, A> from r
    removed: IntoIter<T, A>
    replacement: I
    pending: List<T, A>
    at: usize
    drop {
        while true {
            match take self.replacement.next() {
                present(value) => {
                    self.pending.push(value)
                },
                none => { break }
            }
        }
        let count = self.pending.len
        self.list.reserve(count)
        let original_len = self.list.len
        // Safety: reservation precedes both moves; pending ownership transfers before any callback.
        unsafe {
            core.ptr.`copy`(
                self.list.ptr.add(self.at).cast_const(),
                self.list.ptr.add(self.at + count),
                original_len - self.at
            )
            core.ptr.`copy`(
                self.pending.ptr.cast_const(),
                self.list.ptr.add(self.at),
                count
            )
        }
        self.pending.len = 0usize
        self.list.len = original_len + count
    }
}
extend<region r, T, A: Allocator, I: Iterator<Item = T>> Splice<region r, T, A, I> implements Iterator {
    type Item = T
    fn size_hint(): (usize, usize?) {
        let remaining = self.removed.len()
        (remaining, present(remaining))
    }
    mut fn next(): T? { self.removed.next() }
}
extend<region r, T, A: Allocator, I: Iterator<Item = T>> Splice<region r, T, A, I> implements BidirectionalIterator {
    mut fn next_back(): T? { self.removed.next_back() }
}
extend<region r, T, A: Allocator, I: Iterator<Item = T>> Splice<region r, T, A, I> implements ExactSizeIterator {}
extend<region r, T, A: Allocator, I: Iterator<Item = T>> Splice<region r, T, A, I> implements FusedIterator {}
extend<T, A: Allocator> IntoIter<T, A> {
    pub fn len(): usize { self.back - self.front }
    pub fn as_slice(): read [T] from self {
        unsafe { read *slice_ptr(self.buf.add(self.front), self.back - self.front) }
    }
    pub mut fn as_mut_slice(): mut [T] from self {
        unsafe { mut *slice_ptr_mut(self.buf.add(self.front), self.back - self.front) }
    }
}
extend<T, A: Allocator> IntoIter<T, A> implements AsRef<[T]> {
    fn as_ref(): read [T] from self { self.as_slice() }
}
extend<T: Clone, A: Allocator + Clone> IntoIter<T, A> implements Clone {
    fn clone(): IntoIter<T, A> {
        var out = with_capacity_in<T, A>(self.back - self.front, self.a.clone())
        var i = self.front
        while i < self.back {
            out.push(unsafe { read *self.buf.add(i) }.clone())
            i += 1usize
        }
        out.into_iter()
    }
}
extend<T: fmt.Debug, A: Allocator> IntoIter<T, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("IntoIter(")
        try fmt.debug_slice(self.as_slice(), mut f)
        try f.write_str(")")
    }
}
extend<T, A: Allocator + Default> IntoIter<T, A> implements Default {
    static fn default(): IntoIter<T, A> { new_in<T, A>(A.(Default).default()).into_iter() }
}

// Borrowed iteration: `for x in read v` yields `read T from v`, `for x in mut v`
// yields `mut T from v`; the loop keeps the vector borrowed.
extend<T, A: Allocator> List<T, A> implements Iterable {
    type Item = T
    type Iter<region r> = SliceIter<region r, T>
    fn iter<region r>(receiver read self: Self from r): SliceIter<region r, T> { self.as_slice().iter() }
}
extend<T, A: Allocator> List<T, A> implements MutableIterable {
    type Item = T
    type IterMut<region r> = SliceIterMut<region r, T>
    fn iter_mut<region r>(receiver mut self: Self from r): SliceIterMut<region r, T> { self.as_mut_slice().iter_mut() }
}

extend<T, A: Allocator> List<T, A> implements ExtendItems<T> {
    mut fn extend<I: OwnedIterable<Item = T>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { self.push(item) }, none => { break } }
        }
    }
}
extend<region r, T: Copy, A: Allocator> List<T, A> implements ExtendItems<read T from r> {
    mut fn extend<I: OwnedIterable<Item = read T from r>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(item) => { self.push(*item) },
                none => { break }
            }
        }
    }
}
extend<T> List<T> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(take items: I): List<T> {
        var out = new<T>()
        out.extend(items)
        out
    }
}

extend<T: fmt.Debug, A: Allocator> List<T, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try fmt.debug_slice(self.as_slice(), mut f)
    }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<T: Transferable, A: Allocator + Transferable> List<T, A> implements Transferable {}
unsafe extend<T: Shareable, A: Allocator + Shareable> List<T, A> implements Shareable {}
// The iterator exclusively owns its allocation and all still-initialized items.
unsafe extend<T: Transferable, A: Allocator + Transferable> IntoIter<T, A> implements Transferable {}
// Shared iterator access only reads items; mutation and destruction are exclusive.
unsafe extend<T: Shareable, A: Allocator + Shareable> IntoIter<T, A> implements Shareable {}
