import core.iter.{Iterator, BidirectionalIterator, ExactSizeIterator, FusedIterator, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems}
import core.clone.Clone
import core.default.Default
import core.cmp.Eq
import core.fmt
import super.alloc.{Allocator, Global, Layout, layout_unchecked, free_block}
import super.collections.TryReserveError
import core.hash.{BuildHasher, Hash, Hasher, SipHasher, sip13}
import super.vec.List
import core.cmp.PartialEq
import core.borrow.KeyView
import core.ops.{BitAnd, BitOr, BitXor, Sub}

fn empty(): usize { 0xffffffffffffffffusize }

fn index_layout(ncap: usize): Layout throws TryReserveError {
    let bytes = match ncap.checked_mul(8usize) {
        present(b) => b,
        none => throw TryReserveError.capacity_overflow()
    }
    if bytes > isize.MAX as usize - 7usize { throw TryReserveError.capacity_overflow() }
    unsafe { layout_unchecked(bytes, 8usize) }
}

pub type Bucket<K, V> {
    pub hash: u64
    pub key: K
    pub value: V
}

pub type DefaultHasher { hasher: SipHasher }
extend DefaultHasher {
    pub static fn new(): DefaultHasher { DefaultHasher(sip13(0u64, 0u64)) }
}
extend DefaultHasher implements Default {
    static fn default(): DefaultHasher { DefaultHasher.new() }
}
extend DefaultHasher implements Hasher {
    mut fn write(read bytes: [u8]): Unit { self.hasher.write(bytes) }
    fn finish(): u64 { self.hasher.finish() }
}

// Entries live densely in a `List` and a power-of-two index table (linear
// probing, backward-shift deletion) maps hashes to entry positions. Both
// blocks come from the same allocator; iteration order is unspecified.
pub copy type DefaultHashBuilder {}
extend DefaultHashBuilder implements Clone {
    fn clone(): DefaultHashBuilder { DefaultHashBuilder() }
}
extend DefaultHashBuilder implements BuildHasher {
    type Hasher = SipHasher
    fn build_hasher(): SipHasher { sip13(0u64, 0u64) }
}
extend DefaultHashBuilder implements Default {
    static fn default(): DefaultHashBuilder { DefaultHashBuilder() }
}

pub type Map<K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> {
    entries: List<Bucket<K, V>, A>
    idx: ptr<mut usize>
    icap: usize
    builder: S
    drop {
        if self.icap != 0usize {
            let layout = unsafe { layout_unchecked(self.icap * 8usize, 8usize) }
            unsafe { self.entries.allocator_mut().deallocate(self.idx.cast<u8>(), layout) }
        }
    }
}

pub type MapDrain<region r, K, V, A: Allocator> {
    inner: super.vec.Drain<region r, Bucket<K, V>, A>
}
extend<region r, K, V, A: Allocator> MapDrain<region r, K, V, A> implements Iterator {
    type Item = (K, V)
    mut fn next(): (K, V)? {
        match take self.inner.next() {
            present(entry) => {
                present((entry.key, entry.value))
            },
            none => none
        }
    }
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}
extend<region r, K, V, A: Allocator> MapDrain<region r, K, V, A> implements BidirectionalIterator {
    mut fn next_back(): (K, V)? {
        match take self.inner.next_back() {
            present(entry) => {
                present((entry.key, entry.value))
            },
            none => none
        }
    }
}
extend<region r, K, V, A: Allocator> MapDrain<region r, K, V, A> implements ExactSizeIterator {}
extend<region r, K: fmt.Debug, V: fmt.Debug, A: Allocator> MapDrain<region r, K, V, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        let entries = self.inner.as_slice()
        try f.write_str("MapDrain(")
        try f.debug_open("{")
        var i = 0usize
        while i < entries.len() {
            let entry = read entries[i]
            try f.debug_item_start(i == 0usize)
            try K.(fmt.Debug).fmt(entry.key, mut f)
            try f.write_str(": ")
            try V.(fmt.Debug).fmt(entry.value, mut f)
            try f.debug_item_end()
            i += 1usize
        }
        try f.debug_close("}", entries.len() == 0usize)
        try f.write_str(")")
    }
}

pub type ExtractIf<region r, K, V, A: Allocator, S: BuildHasher, F> {
    map: mut Map<K, V, A, S> from r
    predicate: F
    index: usize
}
extend<region r, K: Hash + PartialEq, V, A: Allocator, S: BuildHasher, F: mut fn(read K, mut V): bool> ExtractIf<region r, K, V, A, S, F> implements Iterator {
    type Item = (K, V)
    mut fn next(): (K, V)? {
        while self.index < self.map.entries.len() {
            let index = self.index
            let entry = unsafe { self.map.entries.as_mut_ptr().add(index) }
            let matches = self.predicate(unsafe { read (*entry).key }, unsafe { mut (*entry).value })
            if matches {
                return present(self.map.remove_index(index))
            }
            self.index += 1usize
        }
        none
    }
}

pub fn new_in<K, V, A: Allocator>(take a: A): Map<K, V, A> {
    Map<K, V, A>(allocator: take a)
}
pub fn new<K, V>(): Map<K, V> { new_in(Global()) }
pub fn with_capacity_in<K: Hash + PartialEq, V, A: Allocator>(capacity: usize, take a: A): Map<K, V, A> {
    var map = new_in<K, V, A>(take a)
    map.reserve(capacity)
    map
}
pub fn with_capacity<K: Hash + PartialEq, V>(capacity: usize): Map<K, V> {
    with_capacity_in(capacity, Global())
}
pub const fn with_hasher<K, V, S: BuildHasher>(take builder: S): Map<K, V, Global, S> {
    let result: Map<K, V, Global, S>
    result.entries = super.vec.new_in<Bucket<K, V>, Global>(Global())
    result.idx = core.ptr.null_mut<usize>()
    result.icap = 0usize
    result.builder = take builder
    result
}
pub fn with_capacity_and_hasher_in<K: Hash + PartialEq, V, A: Allocator, S: BuildHasher>(
    capacity: usize,
    take allocator: A,
    take builder: S
): Map<K, V, A, S> {
    var map = Map<K, V, A, S>(allocator: take allocator, builder: take builder)
    map.reserve(capacity)
    map
}
pub fn with_capacity_and_hasher<K: Hash + PartialEq, V, S: BuildHasher>(
    capacity: usize,
    take builder: S
): Map<K, V, Global, S> {
    with_capacity_and_hasher_in(capacity, Global(), take builder)
}

extend<K, V> Map<K, V> {
    pub init() {
        self.entries = super.vec.new<Bucket<K, V>>()
        self.idx = core.ptr.null_mut<usize>()
        self.icap = 0usize
        self.builder = DefaultHashBuilder()
    }
}

extend<K, V, A: Allocator> Map<K, V, A> {
    pub init(take allocator: A) {
        self.entries = super.vec.new_in<Bucket<K, V>, A>(take allocator)
        self.idx = core.ptr.null_mut<usize>()
        self.icap = 0usize
        self.builder = DefaultHashBuilder()
    }
}

extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub init(take allocator: A, take builder: S) {
        self.entries = super.vec.new_in<Bucket<K, V>, A>(take allocator)
        self.idx = core.ptr.null_mut<usize>()
        self.icap = 0usize
        self.builder = take builder
    }
}

extend<K: Hash + PartialEq, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub fn len(): usize { self.entries.len() }
    pub fn is_empty(): bool { self.entries.is_empty() }
    pub fn capacity(): usize {
        let index_capacity = self.icap / 4usize * 3usize
        let entry_capacity = self.entries.capacity()
        if index_capacity < entry_capacity { index_capacity } else { entry_capacity }
    }
    pub fn allocator(): read A from self { self.entries.allocator() }
    // Dense entries; callers must not depend on their iteration order.
    pub fn as_entries(): read [Bucket<K, V>] from self { self.entries.as_slice() }

    fn slot(pos: usize): usize { unsafe { *self.idx.add(pos) } }
    fn set_slot(pos: usize, entry: usize): Unit { unsafe { *self.idx.add(pos) = entry } }

    // Index-table position holding the entry whose key views as `key`.
    fn find_pos<Q: PartialEq + unsized>(hash: u64, read key: Q): usize? where K: KeyView<Q> {
        if self.icap == 0usize { return none }
        let mask = self.icap - 1usize
        var pos = (hash as usize) & mask
        while true {
            let s = self.slot(pos)
            if s == empty() { return none }
            let hit = match self.entries.get(s) {
                present(e) => e.hash == hash && Q.(PartialEq<Q>).eq(K.(KeyView<Q>).key_view(e.key), key),
                none => false
            }
            if hit { return present(pos) }
            pos = (pos + 1usize) & mask
        }
        none
    }
    fn find_entry<Q: Hash + PartialEq + unsized>(read key: Q): usize? where K: KeyView<Q> {
        let hash = self.builder.hash_one(key)
        match self.find_pos(hash, key) {
            present(pos) => present(self.slot(pos)),
            none => none
        }
    }

    mut fn install_index(nidx: ptr<mut usize>, ncap: usize): Unit {
        var i = 0usize
        while i < ncap {
            unsafe { *nidx.add(i) = empty() }
            i += 1usize
        }
        let mask = ncap - 1usize
        var e = 0usize
        while e < self.entries.len() {
            let h = match self.entries.get(e) { present(b) => b.hash, none => 0u64 }
            var pos = (h as usize) & mask
            while unsafe { *nidx.add(pos) } != empty() { pos = (pos + 1usize) & mask }
            unsafe { *nidx.add(pos) = e }
            e += 1usize
        }
        let old_index = self.idx
        let old_capacity = self.icap
        self.idx = nidx
        self.icap = ncap
        if old_capacity != 0usize {
            let old = unsafe { layout_unchecked(old_capacity * 8usize, 8usize) }
            unsafe { self.entries.allocator_mut().deallocate(old_index.cast<u8>(), old) }
        }
    }

    mut fn rebuild(ncap: usize): Unit throws TryReserveError {
        let layout = try index_layout(ncap)
        let np = match capture self.entries.allocator_mut().allocate(layout) {
            success(p) => p,
            failure(_) => throw TryReserveError.allocation_error(layout)
        }
        self.install_index(np.cast<usize>(), ncap)
    }

    mut fn try_reserve_impl(extra: usize, exact: bool): Unit throws TryReserveError {
        let need = match (self.entries.len()).checked_add(extra) {
            present(n) => n,
            none => throw TryReserveError.capacity_overflow()
        }
        if need <= self.capacity() { return () }
        try self.entries.check_reserve(extra, exact)
        var ncap = if self.icap == 0usize { 8usize } else { self.icap }
        while need > ncap - ncap / 4usize {
            if ncap > isize.MAX as usize / 2usize {
                throw TryReserveError.capacity_overflow()
            }
            ncap *= 2usize
        }
        if ncap == self.icap {
            if exact { try self.entries.try_reserve_exact(extra) }
            else { try self.entries.try_reserve(extra) }
            return ()
        }
        let layout = try index_layout(ncap)
        let np = match capture self.entries.allocator_mut().allocate(layout) {
            success(p) => p,
            failure(_) => throw TryReserveError.allocation_error(layout)
        }
        let guard = unsafe {
            free_block(np, layout, core.ptr.from_mut(*self.entries.allocator_mut()))
        }
        if exact { try self.entries.try_reserve_exact(extra) }
        else { try self.entries.try_reserve(extra) }
        core.mem.forget(take guard)
        self.install_index(np.cast<usize>(), ncap)
    }
    pub mut fn try_reserve(extra: usize): Unit throws TryReserveError {
        try self.try_reserve_impl(extra, false)
    }
    pub mut fn try_reserve_exact(extra: usize): Unit throws TryReserveError {
        try self.try_reserve_impl(extra, true)
    }
    pub mut fn reserve(extra: usize): Unit {
        match capture self.try_reserve(extra) {
            success(_) => (),
            failure(error) => error.handle()
        }
    }
    pub mut fn reserve_exact(extra: usize): Unit {
        match capture self.try_reserve_exact(extra) {
            success(_) => (),
            failure(error) => error.handle()
        }
    }
    pub mut fn shrink_to_fit(): Unit {
        var target = 0usize
        if self.entries.len() != 0usize {
            target = 8usize
            while self.entries.len() > target - target / 4usize {
                target *= 2usize
            }
        }
        if target == 0usize && self.icap != 0usize {
            let old = unsafe { layout_unchecked(self.icap * 8usize, 8usize) }
            let old_index = self.idx
            self.idx = core.ptr.null_mut<usize>()
            self.icap = 0usize
            unsafe {
                self.entries.allocator_mut().deallocate(old_index.cast<u8>(), old)
            }
        } else if target < self.icap {
            match capture self.rebuild(target) {
                success(_) => (),
                failure(_) => ()
            }
        }
        self.entries.shrink_to_fit()
    }
    pub mut fn shrink_to(min_capacity: usize): Unit {
        let old_capacity = self.capacity()
        if old_capacity <= min_capacity { return () }
        let wanted = if min_capacity > self.entries.len() { min_capacity } else { self.entries.len() }
        var target = 0usize
        if wanted != 0usize {
            target = 8usize
            while wanted > target - target / 4usize {
                if target > isize.MAX as usize / 2usize { return () }
                target *= 2usize
            }
        }
        if target == 0usize && self.icap != 0usize {
            let old = unsafe { layout_unchecked(self.icap * 8usize, 8usize) }
            unsafe { self.entries.allocator_mut().deallocate(self.idx.cast<u8>(), old) }
            self.idx = core.ptr.null_mut<usize>()
            self.icap = 0usize
        } else if target < self.icap {
            match capture self.rebuild(target) {
                success(_) => (),
                failure(_) => ()
            }
        }
        self.entries.shrink_to(min_capacity)
    }

    // Lookups take a borrowed query `Q` that the stored key views as (a
    // `String` key is searched with a `Text`); equal keys and queries must hash
    // alike (see `KeyView`).
    pub fn contains_key<Q: Hash + PartialEq + unsized>(read key: Q): bool where K: KeyView<Q> {
        match self.find_entry(key) { present(_) => true, none => false }
    }
    pub fn get<Q: Hash + PartialEq + unsized>(read key: Q): (read V from self)? where K: KeyView<Q> {
        match self.find_entry(key) {
            present(s) => match self.entries.get(s) { present(e) => present(read e.value), none => none },
            none => none
        }
    }
    pub fn get_key_value<Q: Hash + PartialEq + unsized>(read key: Q): (read K from self, read V from self)? where K: KeyView<Q> {
        match self.find_entry(key) {
            present(s) => match self.entries.get(s) {
                present(e) => present((read e.key, read e.value)),
                none => none
            },
            none => none
        }
    }
    pub mut fn get_mut<Q: Hash + PartialEq + unsized>(read key: Q): (mut V from self)? where K: KeyView<Q> {
        match self.find_entry(key) {
            present(s) => present(unsafe { mut (*self.entries.as_mut_ptr().add(s)).value }),
            none => none
        }
    }
    pub mut fn get_disjoint_mut<Q: Hash + PartialEq + unsized, R: Hash + PartialEq + unsized>(
        read first: Q,
        read second: R
    ): (mut V from self, mut V from self)? where K: KeyView<Q> + KeyView<R> {
        let first_index = self.find_entry(first)
        let second_index = self.find_entry(second)
        match first_index {
            present(i) => match second_index {
                present(j) => {
                    if i == j { super.alloc.panic_precondition() }
                    let entries = self.entries.as_mut_ptr()
                    present((
                        unsafe { mut (*entries.add(i)).value },
                        unsafe { mut (*entries.add(j)).value }
                    ))
                },
                none => none
            },
            none => none
        }
    }
    // Safety: both keys must exist and designate distinct entries.
    pub mut unsafe fn get_disjoint_unchecked_mut<Q: Hash + PartialEq + unsized, R: Hash + PartialEq + unsized>(
        read first: Q,
        read second: R
    ): (mut V from self, mut V from self) where K: KeyView<Q> + KeyView<R> {
        let i = match self.find_entry(first) {
            present(index) => index,
            none => core.panic.unreachable()
        }
        let j = match self.find_entry(second) {
            present(index) => index,
            none => core.panic.unreachable()
        }
        if i == j { core.panic.unreachable() }
        let entries = self.entries.as_mut_ptr()
        (mut (*entries.add(i)).value, mut (*entries.add(j)).value)
    }
    pub mut fn extract_if<F: mut fn(read K, mut V): bool>(
        take predicate: F
    ): ExtractIf<region self, K, V, A, S, F> {
        ExtractIf(mut self, predicate, 0usize)
    }
    pub mut fn retain<F: mut fn(read K, mut V): bool>(take predicate: F): Unit {
        var keep = predicate
        var index = 0usize
        while index < self.entries.len() {
            let entry = unsafe { self.entries.as_mut_ptr().add(index) }
            if keep(unsafe { read (*entry).key }, unsafe { mut (*entry).value }) {
                index += 1usize
            } else {
                let _removed = self.remove_index(index)
            }
        }
    }

    // Inserts or replaces; a replaced value is returned. On allocation failure
    // the map is unchanged and the pair is dropped.
    pub mut fn try_insert(take key: K, take value: V): V? throws TryReserveError {
        let hash = self.builder.hash_one(key)
        match self.find_pos(hash, key) {
            present(pos) => {
                let s = self.slot(pos)
                let slot = unsafe { core.ptr.from_mut((*self.entries.as_mut_ptr().add(s)).value) }
                return present(unsafe { core.ptr.replace(slot, value) })
            },
            none => {}
        }
        let _ = try self.try_append(hash, key, value)
        none
    }

    mut fn try_append(hash: u64, take key: K, take value: V): usize throws TryReserveError {
        try self.try_reserve(1usize)
        let at = self.entries.len()
        self.entries.push(Bucket(hash, key, value))
        let mask = self.icap - 1usize
        var pos = (hash as usize) & mask
        while self.slot(pos) != empty() { pos = (pos + 1usize) & mask }
        self.set_slot(pos, at)
        at
    }
    pub mut fn insert(take key: K, take value: V): V? {
        let outcome = capture self.try_insert(key, value)
        match take outcome {
            success(old) => old,
            failure(error) => error.handle()
        }
    }

    // Returns the value for `key`, inserting `value` first when absent.
    pub mut fn or_insert(take key: K, take value: V): mut V from self {
        let hash = self.builder.hash_one(key)
        let s = match self.find_pos(hash, key) {
            present(pos) => self.slot(pos),
            none => {
                match capture self.try_append(hash, key, value) {
                    success(index) => index,
                    failure(error) => error.handle()
                }
            }
        }
        unsafe { mut (*self.entries.as_mut_ptr().add(s)).value }
    }

    mut fn remove_at(s: usize, pos: usize): (K, V) {
        let mask = self.icap - 1usize
        var hole = pos
        var j = (pos + 1usize) & mask
        while true {
            let t = self.slot(j)
            if t == empty() { break }
            let home = match self.entries.get(t) { present(e) => (e.hash as usize) & mask, none => 0usize }
            if (j.wrapping_sub(home) & mask) >= (j.wrapping_sub(hole) & mask) {
                self.set_slot(hole, t)
                hole = j
            }
            j = (j + 1usize) & mask
        }
        self.set_slot(hole, empty())
        let last = self.entries.len() - 1usize
        if s != last {
            let h = match self.entries.get(last) { present(e) => e.hash, none => 0u64 }
            var p = (h as usize) & mask
            while self.slot(p) != last { p = (p + 1usize) & mask }
            self.set_slot(p, s)
        }
        let b = self.entries.swap_remove(s)
        (b.key, b.value)
    }
    mut fn remove_index(s: usize): (K, V) {
        let hash = match self.entries.get(s) {
            present(entry) => entry.hash,
            none => core.panic.unreachable()
        }
        let mask = self.icap - 1usize
        var pos = (hash as usize) & mask
        while self.slot(pos) != s {
            if self.slot(pos) == empty() { core.panic.unreachable() }
            pos = (pos + 1usize) & mask
        }
        self.remove_at(s, pos)
    }
    pub mut fn remove_entry<Q: Hash + PartialEq + unsized>(read key: Q): (K, V)? where K: KeyView<Q> {
        let hash = self.builder.hash_one(key)
        let pos = match self.find_pos(hash, key) { present(p) => p, none => { return none } }
        let s = self.slot(pos)
        present(self.remove_at(s, pos))
    }
    pub mut fn remove<Q: Hash + PartialEq + unsized>(read key: Q): V? where K: KeyView<Q> {
        match take self.remove_entry(key) {
            present(entry) => present(entry.1),
            none => none
        }
    }

    pub mut fn clear(): Unit {
        var i = 0usize
        while i < self.icap {
            self.set_slot(i, empty())
            i += 1usize
        }
        self.entries.clear()
    }

    pub mut fn drain(): MapDrain<region self, K, V, A> {
        var i = 0usize
        while i < self.icap {
            self.set_slot(i, empty())
            i += 1usize
        }
        let count = self.entries.len()
        MapDrain(self.entries.drain(0usize..count))
    }
}

extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub fn hasher(): read S from self { read self.builder }
}
extend<K: Hash + PartialEq, V, A: Allocator, S: BuildHasher, Q: Hash + PartialEq + unsized> Map<K, V, A, S> implements core.ops.Index<Q> where K: KeyView<Q> {
    type Output = V
    fn index(read key: Q): read V from self {
        match self.get(key) {
            present(value) => value,
            none => super.alloc.panic_precondition()
        }
    }
}

// Set of keys backed by a map with unit values.
pub type Set<K, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> { map: Map<K, Unit, A, S> }

const fn set_from_map<K, A: Allocator, S: BuildHasher>(take map: Map<K, Unit, A, S>): Set<K, A, S> {
    let result: Set<K, A, S>
    result.map = take map
    result
}

pub fn set_new_in<K, A: Allocator>(take a: A): Set<K, A> {
    Set<K, A>(allocator: take a)
}
pub fn set_new<K>(): Set<K> { Set<K>() }
pub fn set_with_capacity_in<K: Hash + PartialEq, A: Allocator>(capacity: usize, take a: A): Set<K, A> {
    var set = set_new_in<K, A>(take a)
    set.reserve(capacity)
    set
}
pub fn set_with_capacity<K: Hash + PartialEq>(capacity: usize): Set<K> {
    set_with_capacity_in(capacity, Global())
}
pub const fn set_with_hasher<K, S: BuildHasher>(take builder: S): Set<K, Global, S> {
    set_from_map(with_hasher<K, Unit, S>(take builder))
}
pub fn set_with_capacity_and_hasher_in<K: Hash + PartialEq, A: Allocator, S: BuildHasher>(
    capacity: usize,
    take allocator: A,
    take builder: S
): Set<K, A, S> {
    set_from_map(with_capacity_and_hasher_in<K, Unit, A, S>(capacity, take allocator, take builder))
}
pub fn set_with_capacity_and_hasher<K: Hash + PartialEq, S: BuildHasher>(
    capacity: usize,
    take builder: S
): Set<K, Global, S> {
    set_with_capacity_and_hasher_in(capacity, Global(), take builder)
}

extend<K> Set<K> {
    pub init() { self.map = new<K, Unit>() }
}

extend<K, A: Allocator> Set<K, A> {
    pub init(take allocator: A) {
        self.map = new_in<K, Unit, A>(take allocator)
    }
}

extend<K, A: Allocator, S: BuildHasher> Set<K, A, S> {
    pub init(take allocator: A, take builder: S) {
        self.map = Map<K, Unit, A, S>(allocator: take allocator, builder: take builder)
    }
}

extend<K: Hash + PartialEq, A: Allocator, S: BuildHasher> Set<K, A, S> {
    pub fn len(): usize { self.map.len() }
    pub fn capacity(): usize { self.map.capacity() }
    pub fn is_empty(): bool { self.map.is_empty() }
    pub mut fn try_reserve(extra: usize): Unit throws TryReserveError {
        try self.map.try_reserve(extra)
    }
    pub mut fn try_reserve_exact(extra: usize): Unit throws TryReserveError {
        try self.map.try_reserve_exact(extra)
    }
    pub mut fn reserve(extra: usize): Unit { self.map.reserve(extra) }
    pub mut fn reserve_exact(extra: usize): Unit { self.map.reserve_exact(extra) }
    pub mut fn shrink_to_fit(): Unit { self.map.shrink_to_fit() }
    pub mut fn shrink_to(min_capacity: usize): Unit { self.map.shrink_to(min_capacity) }
    pub fn contains<Q: Hash + PartialEq + unsized>(read key: Q): bool where K: KeyView<Q> { self.map.contains_key(key) }
    pub fn get<Q: Hash + PartialEq + unsized>(read key: Q): (read K from self)? where K: KeyView<Q> {
        match self.map.find_entry(key) {
            present(index) => match self.map.entries.get(index) {
                present(entry) => present(read entry.key),
                none => none
            },
            none => none
        }
    }
    // True when the key was newly added.
    pub mut fn insert(take key: K): bool {
        match self.map.insert(key, ()) { present(_) => false, none => true }
    }
    pub mut fn try_insert(take key: K): bool throws TryReserveError {
        match try self.map.try_insert(key, ()) { present(_) => false, none => true }
    }
    pub mut fn remove<Q: Hash + PartialEq + unsized>(read key: Q): bool where K: KeyView<Q> {
        match self.map.remove(key) { present(_) => true, none => false }
    }
    pub mut fn `take`<Q: Hash + PartialEq + unsized>(read key: Q): K? where K: KeyView<Q> {
        match take self.map.remove_entry(key) {
            present(entry) => present(entry.0),
            none => none
        }
    }
    pub mut fn replace(take value: K): K? {
        let hash = self.map.builder.hash_one(value)
        match self.map.find_pos(hash, value) {
            present(pos) => {
                let index = self.map.slot(pos)
                let entries = self.map.entries.as_mut_ptr()
                // The exclusive receiver keeps this live entry stable; equal
                // keys preserve the hash and probing position.
                let key_slot = unsafe { core.ptr.from_mut((*entries.add(index)).key) }
                present(unsafe { core.ptr.replace(key_slot, value) })
            },
            none => {
                let _old = self.map.insert(value, ())
                none
            }
        }
    }
    pub mut fn clear(): Unit { self.map.clear() }
    pub fn as_entries(): read [Bucket<K, Unit>] from self { self.map.as_entries() }
}

extend<K, A: Allocator, S: BuildHasher> Set<K, A, S> {
    pub fn hasher(): read S from self { self.map.hasher() }
}

pub type SetDrain<region r, K, A: Allocator> {
    inner: MapDrain<region r, K, Unit, A>
}
extend<region r, K, A: Allocator> SetDrain<region r, K, A> implements Iterator {
    type Item = K
    mut fn next(): K? {
        match take self.inner.next() {
            present(entry) => present(entry.0),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}
extend<region r, K, A: Allocator> SetDrain<region r, K, A> implements BidirectionalIterator {
    mut fn next_back(): K? {
        match take self.inner.next_back() {
            present(entry) => present(entry.0),
            none => none
        }
    }
}
extend<region r, K, A: Allocator> SetDrain<region r, K, A> implements ExactSizeIterator {}
extend<region r, K: fmt.Debug, A: Allocator> SetDrain<region r, K, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        let entries = self.inner.inner.as_slice()
        try f.write_str("SetDrain(")
        try f.debug_open("{")
        var i = 0usize
        while i < entries.len() {
            try f.debug_item_start(i == 0usize)
            try K.(fmt.Debug).fmt(entries[i].key, mut f)
            try f.debug_item_end()
            i += 1usize
        }
        try f.debug_close("}", entries.len() == 0usize)
        try f.write_str(")")
    }
}

pub type SetExtractIf<region r, K, A: Allocator, S: BuildHasher, F> {
    set: mut Set<K, A, S> from r
    predicate: F
    index: usize
}
extend<region r, K: Hash + PartialEq, A: Allocator, S: BuildHasher, F: mut fn(read K): bool> SetExtractIf<region r, K, A, S, F> implements Iterator {
    type Item = K
    mut fn next(): K? {
        while self.index < self.set.map.entries.len() {
            let index = self.index
            let entry = unsafe { self.set.map.entries.as_mut_ptr().add(index) }
            if self.predicate(unsafe { read (*entry).key }) {
                return present(self.set.map.remove_index(index).0)
            }
            self.index += 1usize
        }
        none
    }
}

// Each algebra iterator scans the left set first, then the right set when its
// operation needs right-only elements. Set iteration order remains unspecified.
pub type SetAlgebra<region r, K, A: Allocator, S: BuildHasher> {
    left: read Set<K, A, S> from r
    right: read Set<K, A, S> from r
    mode: u8
    side: u8
    index: usize
}
extend<region r, K: Hash + PartialEq, A: Allocator, S: BuildHasher> SetAlgebra<region r, K, A, S> implements Iterator {
    type Item = read K from r
    mut fn next(): (read K from r)? {
        while self.side < 2u8 {
            if (self.mode == 1u8 || self.mode == 2u8) && self.side == 1u8 { return none }
            if self.side == 0u8 {
                if self.index >= self.left.map.entries.len() {
                    self.side = 1u8
                    self.index = 0usize
                    continue
                }
                let i = self.index
                self.index += 1usize
                let key = read self.left.map.entries[i].key
                if self.mode == 0u8 { return present(key) }
                let in_right = match self.right.map.find_entry(key) {
                    present(_) => true,
                    none => false
                }
                let include = match self.mode {
                    1u8 => in_right,
                    2u8 => !in_right,
                    _ => !in_right
                }
                if include { return present(read self.left.map.entries[i].key) }
            } else {
                if self.index >= self.right.map.entries.len() { return none }
                let i = self.index
                self.index += 1usize
                let key = read self.right.map.entries[i].key
                let in_left = match self.left.map.find_entry(key) {
                    present(_) => true,
                    none => false
                }
                if (self.mode == 0u8 || self.mode == 3u8) && !in_left {
                    return present(read self.right.map.entries[i].key)
                }
            }
        }
        none
    }
}

extend<K: Hash + PartialEq, A: Allocator, S: BuildHasher> Set<K, A, S> {
    pub fn `union`(read other: Set<K, A, S> from self): SetAlgebra<region self, K, A, S> {
        SetAlgebra(read self, read other, 0u8, 0u8, 0usize)
    }
    pub fn intersection(read other: Set<K, A, S> from self): SetAlgebra<region self, K, A, S> {
        SetAlgebra(read self, read other, 1u8, 0u8, 0usize)
    }
    pub fn difference(read other: Set<K, A, S> from self): SetAlgebra<region self, K, A, S> {
        SetAlgebra(read self, read other, 2u8, 0u8, 0usize)
    }
    pub fn symmetric_difference(read other: Set<K, A, S> from self): SetAlgebra<region self, K, A, S> {
        SetAlgebra(read self, read other, 3u8, 0u8, 0usize)
    }
    pub fn is_subset(read other: Set<K, A, S>): bool {
        var i = 0usize
        while i < self.map.entries.len() {
            if !other.contains(self.map.entries[i].key) { return false }
            i += 1usize
        }
        true
    }
    pub fn is_superset(read other: Set<K, A, S>): bool {
        var i = 0usize
        while i < other.map.entries.len() {
            if !self.contains(other.map.entries[i].key) { return false }
            i += 1usize
        }
        true
    }
    pub fn is_disjoint(read other: Set<K, A, S>): bool {
        var i = 0usize
        while i < self.map.entries.len() {
            if other.contains(self.map.entries[i].key) { return false }
            i += 1usize
        }
        true
    }
    pub mut fn drain(): SetDrain<region self, K, A> { SetDrain(self.map.drain()) }
    pub mut fn extract_if<F: mut fn(read K): bool>(
        take predicate: F
    ): SetExtractIf<region self, K, A, S, F> {
        SetExtractIf(mut self, predicate, 0usize)
    }
    pub mut fn retain<F: mut fn(read K): bool>(take predicate: F): Unit {
        var keep = predicate
        var index = 0usize
        while index < self.map.entries.len() {
            let entry = unsafe { self.map.entries.as_mut_ptr().add(index) }
            if keep(unsafe { read (*entry).key }) {
                index += 1usize
            } else {
                let _removed = self.map.remove_index(index)
            }
        }
    }
}


// Map iteration is in insertion order and yields the stored buckets. Keys are
// never exposed mutably because that could break the table's hash invariants.
pub type Iter<region r, K, V> {
    items: (read [Bucket<K, V>] from r)?
    front: usize
    back: usize
}
extend<region r, K, V> Iter<region r, K, V> implements Iterator {
    type Item = read Bucket<K, V> from r
    mut fn next(): (read Bucket<K, V> from r)? {
        if self.front >= self.back { return none }
        let index = self.front
        self.front += 1usize
        match read self.items {
            present(items) => present(read items[index]),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.front
        (remaining, present(remaining))
    }
}
extend<region r, K, V> Iter<region r, K, V> implements Clone {
    fn clone(): Iter<region r, K, V> { Iter(self.items, self.front, self.back) }
}
extend<region r, K, V> Iter<region r, K, V> implements ExactSizeIterator {}
extend<region r, K, V> Iter<region r, K, V> implements Default {
    static fn default(): Iter<region r, K, V> { Iter(none, 0usize, 0usize) }
}
extend<region r, K: fmt.Debug, V: fmt.Debug> Iter<region r, K, V> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("Iter(")
        try f.debug_open("[")
        var index = self.front
        while index < self.back {
            match read self.items {
                present(items) => {
                    try f.debug_item_start(index == self.front)
                    try K.(fmt.Debug).fmt(items[index].key, mut f)
                    try f.write_str(": ")
                    try V.(fmt.Debug).fmt(items[index].value, mut f)
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
extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> implements Iterable {
    type Item = Bucket<K, V>
    type Iter<region r> = Iter<region r, K, V>
    fn iter<region r>(receiver read self: Self from r): Iter<region r, K, V> {
        Iter(present(self.entries.as_slice()), 0usize, self.entries.len())
    }
}
extend<K, A: Allocator, S: BuildHasher> Set<K, A, S> implements Iterable {
    type Item = K
    type Iter<region r> = Keys<region r, K, Unit>
    fn iter<region r>(receiver read self: Self from r): Keys<region r, K, Unit> {
        Keys(present(self.map.entries.as_slice()), 0usize, self.map.entries.len())
    }
}

// Consuming iteration moves out entries without consulting the now-stale
// index; dropping the iterator releases the remaining buckets and index block.
pub type MapIntoIter<K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> { map: Map<K, V, A, S> }
extend<K, V, A: Allocator, S: BuildHasher> MapIntoIter<K, V, A, S> implements Iterator {
    type Item = (K, V)
    mut fn next(): (K, V)? {
        match take self.map.entries.pop() {
            present(entry) => present((entry.key, entry.value)),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) {
        let remaining = self.map.entries.len()
        (remaining, present(remaining))
    }
}
extend<K, V, A: Allocator, S: BuildHasher> MapIntoIter<K, V, A, S> implements ExactSizeIterator {}
extend<K: fmt.Debug, V: fmt.Debug, A: Allocator, S: BuildHasher> MapIntoIter<K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("MapIntoIter(")
        try Map<K, V, A, S>.(fmt.Debug).fmt(read self.map, mut f)
        try f.write_str(")")
    }
}
extend<K: Hash + PartialEq, V, A: Allocator + Default, S: BuildHasher + Default> MapIntoIter<K, V, A, S> implements Default {
    static fn default(): MapIntoIter<K, V, A, S> {
        MapIntoIter(Map<K, V, A, S>.(Default).default())
    }
}
extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> implements OwnedIterable {
    type Item = (K, V)
    type IntoIter = MapIntoIter<K, V, A, S>
    fn into_iter(receiver take self: Self): MapIntoIter<K, V, A, S> {
        MapIntoIter(take self)
    }
}

extend<K: Hash + PartialEq, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub take fn into_keys(): IntoKeys<K, V, A, S> { IntoKeys(self.into_iter()) }
    pub take fn into_values(): IntoValues<K, V, A, S> { IntoValues(self.into_iter()) }
}
pub type IntoKeys<K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> { inner: MapIntoIter<K, V, A, S> }
extend<K, V, A: Allocator, S: BuildHasher> IntoKeys<K, V, A, S> implements Iterator {
    type Item = K
    mut fn next(): K? {
        match take self.inner.next() {
            present(entry) => present(entry.0),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}
extend<K, V, A: Allocator, S: BuildHasher> IntoKeys<K, V, A, S> implements ExactSizeIterator {}
extend<K: fmt.Debug, V, A: Allocator, S: BuildHasher> IntoKeys<K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        let entries = self.inner.map.entries.as_slice()
        try f.write_str("IntoKeys(")
        try f.debug_open("[")
        var i = 0usize
        while i < entries.len() {
            try f.debug_item_start(i == 0usize)
            try K.(fmt.Debug).fmt(entries[i].key, mut f)
            try f.debug_item_end()
            i += 1usize
        }
        try f.debug_close("]", entries.len() == 0usize)
        try f.write_str(")")
    }
}
extend<K: Hash + PartialEq, V, A: Allocator + Default, S: BuildHasher + Default> IntoKeys<K, V, A, S> implements Default {
    static fn default(): IntoKeys<K, V, A, S> {
        IntoKeys(MapIntoIter<K, V, A, S>.(Default).default())
    }
}
pub type IntoValues<K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> { inner: MapIntoIter<K, V, A, S> }
extend<K, V, A: Allocator, S: BuildHasher> IntoValues<K, V, A, S> implements Iterator {
    type Item = V
    mut fn next(): V? {
        match take self.inner.next() {
            present(entry) => present(entry.1),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}
extend<K, V, A: Allocator, S: BuildHasher> IntoValues<K, V, A, S> implements ExactSizeIterator {}
extend<K, V: fmt.Debug, A: Allocator, S: BuildHasher> IntoValues<K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        let entries = self.inner.map.entries.as_slice()
        try f.write_str("IntoValues(")
        try f.debug_open("[")
        var i = 0usize
        while i < entries.len() {
            try f.debug_item_start(i == 0usize)
            try V.(fmt.Debug).fmt(entries[i].value, mut f)
            try f.debug_item_end()
            i += 1usize
        }
        try f.debug_close("]", entries.len() == 0usize)
        try f.write_str(")")
    }
}
extend<K: Hash + PartialEq, V, A: Allocator + Default, S: BuildHasher + Default> IntoValues<K, V, A, S> implements Default {
    static fn default(): IntoValues<K, V, A, S> {
        IntoValues(MapIntoIter<K, V, A, S>.(Default).default())
    }
}

pub type SetIntoIter<K, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> { inner: MapIntoIter<K, Unit, A, S> }
extend<K, A: Allocator, S: BuildHasher> SetIntoIter<K, A, S> implements Iterator {
    type Item = K
    mut fn next(): K? {
        match take self.inner.next() {
            present(pair) => present(pair.0),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}
extend<K, A: Allocator, S: BuildHasher> SetIntoIter<K, A, S> implements ExactSizeIterator {}
extend<K: fmt.Debug, A: Allocator, S: BuildHasher> SetIntoIter<K, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        let entries = self.inner.map.entries.as_slice()
        try f.debug_open("{")
        var i = 0usize
        while i < entries.len() {
            try f.debug_item_start(i == 0usize)
            try K.(fmt.Debug).fmt(entries[i].key, mut f)
            try f.debug_item_end()
            i += 1usize
        }
        try f.debug_close("}", entries.len() == 0usize)
    }
}
extend<K: Hash + PartialEq, A: Allocator + Default, S: BuildHasher + Default> SetIntoIter<K, A, S> implements Default {
    static fn default(): SetIntoIter<K, A, S> {
        SetIntoIter(MapIntoIter<K, Unit, A, S>.(Default).default())
    }
}
extend<K, A: Allocator, S: BuildHasher> Set<K, A, S> implements OwnedIterable {
    type Item = K
    type IntoIter = SetIntoIter<K, A, S>
    fn into_iter(receiver take self: Self): SetIntoIter<K, A, S> {
        SetIntoIter(self.map.into_iter())
    }
}

// The exclusive map borrow keeps entries dense and stable; advancing the
// cursor before yielding ensures each mutable value slot is issued only once.
pub type IterMut<region r, K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> {
    map: (mut Map<K, V, A, S> from r)?
    index: usize
}
extend<region r, K, V, A: Allocator, S: BuildHasher> IterMut<region r, K, V, A, S> implements Iterator {
    type Item = (read K from r, mut V from r)
    mut fn next(): (read K from r, mut V from r)? {
        match mut self.map {
            present(map) => {
                if self.index >= map.entries.len() { return none }
                let i = self.index
                self.index += 1usize
                let entry = unsafe { map.entries.as_mut_ptr().add(i) }
                present((unsafe { read (*entry).key }, unsafe { mut (*entry).value }))
            },
            none => none
        }
    }
    fn size_hint(): (usize, usize?) {
        match read self.map {
            present(map) => {
                let remaining = map.entries.len() - self.index
                (remaining, present(remaining))
            },
            none => (0usize, present(0usize))
        }
    }
}
extend<region r, K, V, A: Allocator, S: BuildHasher> IterMut<region r, K, V, A, S> implements ExactSizeIterator {}
extend<region r, K, V, A: Allocator, S: BuildHasher> IterMut<region r, K, V, A, S> implements Default {
    static fn default(): IterMut<region r, K, V, A, S> { IterMut(none, 0usize) }
}
extend<region r, K: fmt.Debug, V: fmt.Debug, A: Allocator, S: BuildHasher> IterMut<region r, K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("IterMut(")
        try f.debug_open("{")
        match read self.map {
            present(map) => {
                var index = self.index
                var first = true
                while index < map.entries.len() {
                    let entry = read map.entries[index]
                    try f.debug_item_start(first)
                    try K.(fmt.Debug).fmt(entry.key, mut f)
                    try f.write_str(": ")
                    try V.(fmt.Debug).fmt(entry.value, mut f)
                    try f.debug_item_end()
                    first = false
                    index += 1usize
                }
            },
            none => {}
        }
        try f.debug_close("}", self.size_hint().0 == 0usize)
        try f.write_str(")")
    }
}
extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub mut fn iter_mut(): IterMut<region self, K, V, A, S> {
        IterMut(present(mut self), 0usize)
    }
}

// Generic mutable iteration visits values only: mutable keys could break the
// table's hash invariants.
pub type ValuesMut<region r, K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> {
    map: (mut Map<K, V, A, S> from r)?
    index: usize
    back: usize
}
extend<region r, K, V, A: Allocator, S: BuildHasher> ValuesMut<region r, K, V, A, S> implements Iterator {
    type Item = mut V from r
    mut fn next(): (mut V from r)? {
        if self.index >= self.back { return none }
        match mut self.map {
            present(map) => {
                let i = self.index
                self.index += 1usize
                present(unsafe { mut (*map.entries.as_mut_ptr().add(i)).value })
            },
            none => none
        }
    }
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.index
        (remaining, present(remaining))
    }
}
extend<region r, K, V, A: Allocator, S: BuildHasher> ValuesMut<region r, K, V, A, S> implements BidirectionalIterator {
    mut fn next_back(): (mut V from r)? {
        if self.index >= self.back { return none }
        match mut self.map {
            present(map) => {
                self.back -= 1usize
                present(unsafe { mut (*map.entries.as_mut_ptr().add(self.back)).value })
            },
            none => none
        }
    }
}
extend<region r, K, V, A: Allocator, S: BuildHasher> ValuesMut<region r, K, V, A, S> implements ExactSizeIterator {}
extend<region r, K, V, A: Allocator, S: BuildHasher> ValuesMut<region r, K, V, A, S> implements Default {
    static fn default(): ValuesMut<region r, K, V, A, S> { ValuesMut(none, 0usize, 0usize) }
}
extend<region r, K, V: fmt.Debug, A: Allocator, S: BuildHasher> ValuesMut<region r, K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("ValuesMut(")
        try f.debug_open("[")
        match read self.map {
            present(map) => {
                var index = self.index
                var first = true
                while index < self.back {
                    try f.debug_item_start(first)
                    try V.(fmt.Debug).fmt(map.entries[index].value, mut f)
                    try f.debug_item_end()
                    first = false
                    index += 1usize
                }
            },
            none => {}
        }
        try f.debug_close("]", self.size_hint().0 == 0usize)
        try f.write_str(")")
    }
}
// Borrowed iterators over the keys or the values only.
pub type Keys<region r, K, V> {
    items: (read [Bucket<K, V>] from r)?
    front: usize
    back: usize
}
extend<region r, K, V> Keys<region r, K, V> implements Iterator {
    type Item = read K from r
    mut fn next(): (read K from r)? {
        if self.front >= self.back { return none }
        let index = self.front
        self.front += 1usize
        match read self.items {
            present(items) => present(read items[index].key),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.front
        (remaining, present(remaining))
    }
}
extend<region r, K, V> Keys<region r, K, V> implements Clone {
    fn clone(): Keys<region r, K, V> { Keys(self.items, self.front, self.back) }
}
extend<region r, K, V> Keys<region r, K, V> implements Default {
    static fn default(): Keys<region r, K, V> { Keys(none, 0usize, 0usize) }
}
extend<region r, K: fmt.Debug, V> Keys<region r, K, V> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("Keys(")
        try f.debug_open("[")
        var index = self.front
        while index < self.back {
            match read self.items {
                present(items) => {
                    try f.debug_item_start(index == self.front)
                    try K.(fmt.Debug).fmt(items[index].key, mut f)
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
extend<region r, K, V> Keys<region r, K, V> implements ExactSizeIterator {}
pub type Values<region r, K, V> {
    items: (read [Bucket<K, V>] from r)?
    front: usize
    back: usize
}
extend<region r, K, V> Values<region r, K, V> implements Iterator {
    type Item = read V from r
    mut fn next(): (read V from r)? {
        if self.front >= self.back { return none }
        let index = self.front
        self.front += 1usize
        match read self.items {
            present(items) => present(read items[index].value),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.front
        (remaining, present(remaining))
    }
}
extend<region r, K, V, A: Allocator> MapDrain<region r, K, V, A> implements FusedIterator {}
extend<region r, K: Hash + PartialEq, V, A: Allocator, S: BuildHasher, F: mut fn(read K, mut V): bool> ExtractIf<region r, K, V, A, S, F> implements FusedIterator {}
extend<region r, K, A: Allocator> SetDrain<region r, K, A> implements FusedIterator {}
extend<region r, K: Hash + PartialEq, A: Allocator, S: BuildHasher, F: mut fn(read K): bool> SetExtractIf<region r, K, A, S, F> implements FusedIterator {}
extend<region r, K: Hash + PartialEq, A: Allocator, S: BuildHasher> SetAlgebra<region r, K, A, S> implements FusedIterator {}
extend<region r, K, V> Iter<region r, K, V> implements FusedIterator {}
extend<K, V, A: Allocator, S: BuildHasher> MapIntoIter<K, V, A, S> implements FusedIterator {}
extend<K, V, A: Allocator, S: BuildHasher> IntoKeys<K, V, A, S> implements FusedIterator {}
extend<K, V, A: Allocator, S: BuildHasher> IntoValues<K, V, A, S> implements FusedIterator {}
extend<K, A: Allocator, S: BuildHasher> SetIntoIter<K, A, S> implements FusedIterator {}
extend<region r, K, V, A: Allocator, S: BuildHasher> IterMut<region r, K, V, A, S> implements FusedIterator {}
extend<region r, K, V, A: Allocator, S: BuildHasher> ValuesMut<region r, K, V, A, S> implements FusedIterator {}
extend<region r, K, V> Keys<region r, K, V> implements FusedIterator {}
extend<region r, K, V> Values<region r, K, V> implements FusedIterator {}
extend<region r, K, V> Values<region r, K, V> implements Clone {
    fn clone(): Values<region r, K, V> { Values(self.items, self.front, self.back) }
}
extend<region r, K, V> Values<region r, K, V> implements Default {
    static fn default(): Values<region r, K, V> { Values(none, 0usize, 0usize) }
}
extend<region r, K, V: fmt.Debug> Values<region r, K, V> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("Values(")
        try f.debug_open("[")
        var index = self.front
        while index < self.back {
            match read self.items {
                present(items) => {
                    try f.debug_item_start(index == self.front)
                    try V.(fmt.Debug).fmt(items[index].value, mut f)
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
extend<region r, K, V> Values<region r, K, V> implements ExactSizeIterator {}
extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub fn keys(): Keys<region self, K, V> {
        Keys(present(self.entries.as_slice()), 0usize, self.entries.len())
    }
    pub fn values(): Values<region self, K, V> {
        Values(present(self.entries.as_slice()), 0usize, self.entries.len())
    }
}
extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> implements MutableIterable {
    type Item = V
    type IterMut<region r> = ValuesMut<region r, K, V, A, S>
    fn iter_mut<region r>(receiver mut self: Self from r): ValuesMut<region r, K, V, A, S> {
        let back = self.entries.len()
        ValuesMut(present(mut self), 0usize, back)
    }
}
extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub mut fn values_mut(): ValuesMut<region self, K, V, A, S> {
        let back = self.entries.len()
        ValuesMut(present(mut self), 0usize, back)
    }
}

extend<K: Hash + PartialEq, V, A: Allocator + Default, S: BuildHasher + Default> Map<K, V, A, S> implements Default {
    static fn default(): Map<K, V, A, S> {
        Map<K, V, A, S>(allocator: A.(Default).default(), builder: S.(Default).default())
    }
}

extend<K: Hash + PartialEq + Clone, V: Clone, A: Allocator + Clone, S: BuildHasher + Clone> Map<K, V, A, S> implements Clone {
    fn clone(): Map<K, V, A, S> {
        var out = Map<K, V, A, S>(allocator: self.entries.allocator().clone(), builder: self.builder.clone())
        var i = 0usize
        while i < self.entries.len() {
            let e = read self.entries[i]
            let old = out.insert(e.key.clone(), e.value.clone())
            i += 1usize
        }
        out
    }
}
// Equal when both hold the same keys with equal values, in any order.
extend<K: Hash + PartialEq, V: PartialEq, A: Allocator, S: BuildHasher, U: BuildHasher> Map<K, V, A, S> implements PartialEq<Map<K, V, A, U>> {
    fn eq(read other: Map<K, V, A, U>): bool {
        if self.len() != other.len() { return false }
        var i = 0usize
        while i < self.entries.len() {
            let e = read self.entries[i]
            match other.find_entry(e.key) {
                present(s) => { if !e.value.eq(other.entries[s].value) { return false } },
                none => { return false }
            }
            i += 1usize
        }
        true
    }
}
extend<K: Hash + PartialEq, V: Eq, A: Allocator, S: BuildHasher> Map<K, V, A, S> implements Eq {}
extend<K: fmt.Debug, V: fmt.Debug, A: Allocator, S: BuildHasher> Map<K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.debug_open("{")
        var i = 0usize
        while i < self.entries.len() {
            let e = read self.entries[i]
            try f.debug_item_start(i == 0usize)
            try K.(fmt.Debug).fmt(e.key, mut f)
            try f.write_str(": ")
            try V.(fmt.Debug).fmt(e.value, mut f)
            try f.debug_item_end()
            i += 1usize
        }
        try f.debug_close("}", self.entries.len() == 0usize)
    }
}
extend<K: Hash + PartialEq, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> implements ExtendItems<(K, V)> {
    mut fn extend<I: OwnedIterable<Item = (K, V)>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(pair) => { let old = self.insert(pair.0, pair.1) },
                none => { break }
            }
        }
    }
}
extend<K: Hash + PartialEq, V> Map<K, V> implements FromItems<(K, V)> {
    static fn from_iter<I: OwnedIterable<Item = (K, V)>>(take items: I): Map<K, V> {
        var out = new<K, V>()
        out.extend(items)
        out
    }
}

extend<K: Hash + PartialEq, V, const N: usize> Map<K, V> implements core.convert.From<[(K, V); N]> {
    static fn from(take items: [(K, V); N]): Map<K, V> {
        var out = new<K, V>()
        for item in take items { let _ = out.insert(item.0, item.1) }
        out
    }
}

extend<K: Hash + PartialEq + Clone, A: Allocator + Clone, S: BuildHasher + Clone> Set<K, A, S> implements Clone {
    fn clone(): Set<K, A, S> { set_from_map(self.map.clone()) }
}
extend<K: Hash + PartialEq, A: Allocator + Default, S: BuildHasher + Default> Set<K, A, S> implements Default {
    static fn default(): Set<K, A, S> { set_from_map(Map<K, Unit, A, S>.(Default).default()) }
}

// The operators build new sets from clones of the operands' elements, as the
// `&a | &b` forms of the baseline do.
extend<K: Hash + PartialEq + Clone, A: Allocator + Clone, S: BuildHasher + Clone> Set<K, A, S> implements BitOr<Set<K, A, S>> {
    type Output = Set<K, A, S>
    fn bitor(read rhs: Set<K, A, S>): Set<K, A, S> {
        var out = self.clone()
        var i = 0usize
        while i < rhs.map.entries.len() {
            out.insert(rhs.map.entries[i].key.clone())
            i += 1usize
        }
        out
    }
}
extend<K: Hash + PartialEq + Clone, A: Allocator + Clone, S: BuildHasher + Clone> Set<K, A, S> implements BitAnd<Set<K, A, S>> {
    type Output = Set<K, A, S>
    fn bitand(read rhs: Set<K, A, S>): Set<K, A, S> {
        var out = set_from_map(Map<K, Unit, A, S>(allocator: self.map.allocator().clone(), builder: self.map.hasher().clone()))
        var i = 0usize
        while i < self.map.entries.len() {
            if rhs.contains(self.map.entries[i].key) {
                let _ = out.insert(self.map.entries[i].key.clone())
            }
            i += 1usize
        }
        out
    }
}
extend<K: Hash + PartialEq + Clone, A: Allocator + Clone, S: BuildHasher + Clone> Set<K, A, S> implements Sub<Set<K, A, S>> {
    type Output = Set<K, A, S>
    fn sub(read rhs: Set<K, A, S>): Set<K, A, S> {
        var out = set_from_map(Map<K, Unit, A, S>(allocator: self.map.allocator().clone(), builder: self.map.hasher().clone()))
        var i = 0usize
        while i < self.map.entries.len() {
            if !rhs.contains(self.map.entries[i].key) {
                let _ = out.insert(self.map.entries[i].key.clone())
            }
            i += 1usize
        }
        out
    }
}
extend<K: Hash + PartialEq + Clone, A: Allocator + Clone, S: BuildHasher + Clone> Set<K, A, S> implements BitXor<Set<K, A, S>> {
    type Output = Set<K, A, S>
    fn bitxor(read rhs: Set<K, A, S>): Set<K, A, S> {
        var out = set_from_map(Map<K, Unit, A, S>(allocator: self.map.allocator().clone(), builder: self.map.hasher().clone()))
        var i = 0usize
        while i < self.map.entries.len() {
            if !rhs.contains(self.map.entries[i].key) {
                let _ = out.insert(self.map.entries[i].key.clone())
            }
            i += 1usize
        }
        i = 0usize
        while i < rhs.map.entries.len() {
            if !self.contains(rhs.map.entries[i].key) {
                let _ = out.insert(rhs.map.entries[i].key.clone())
            }
            i += 1usize
        }
        out
    }
}
// Equal when both hold the same elements, in any order.
extend<K: Hash + PartialEq, A: Allocator, S: BuildHasher, U: BuildHasher> Set<K, A, S> implements PartialEq<Set<K, A, U>> {
    fn eq(read other: Set<K, A, U>): bool {
        if self.len() != other.len() { return false }
        var i = 0usize
        while i < self.map.entries.len() {
            match other.map.find_entry(self.map.entries[i].key) {
                present(_) => {},
                none => { return false }
            }
            i += 1usize
        }
        true
    }
}
extend<K: Hash + PartialEq, A: Allocator, S: BuildHasher> Set<K, A, S> implements Eq {}
extend<K: fmt.Debug, A: Allocator, S: BuildHasher> Set<K, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.debug_open("{")
        var i = 0usize
        while i < self.map.entries.len() {
            try f.debug_item_start(i == 0usize)
            try K.(fmt.Debug).fmt(self.map.entries[i].key, mut f)
            try f.debug_item_end()
            i += 1usize
        }
        try f.debug_close("}", self.map.entries.len() == 0usize)
    }
}
extend<K: Hash + PartialEq, A: Allocator, S: BuildHasher> Set<K, A, S> implements ExtendItems<K> {
    mut fn extend<I: OwnedIterable<Item = K>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { let added = self.insert(item) }, none => { break } }
        }
    }
}
extend<K: Hash + PartialEq> Set<K> implements FromItems<K> {
    static fn from_iter<I: OwnedIterable<Item = K>>(take items: I): Set<K> {
        var out = set_new<K>()
        out.extend(items)
        out
    }
}

extend<K: Hash + PartialEq, const N: usize> Set<K> implements core.convert.From<[K; N]> {
    static fn from(take items: [K; N]): Set<K> {
        var out = set_new<K>()
        for item in take items { let _ = out.insert(item) }
        out
    }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<K: Transferable, V: Transferable, A: Allocator + Transferable, S: BuildHasher + Transferable> Map<K, V, A, S> implements Transferable {}
unsafe extend<K: Shareable, V: Shareable, A: Allocator + Shareable, S: BuildHasher + Shareable> Map<K, V, A, S> implements Shareable {}

// An entry owns the query key and exclusively borrows its map until consumed.
// The occupied index remains valid because the loan excludes map mutation.
pub type OccupiedEntry<region r, K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> {
    map: mut Map<K, V, A, S> from r
    index: usize
}
pub type VacantEntry<region r, K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> {
    map: mut Map<K, V, A, S> from r
    key: K
}
pub enum Entry<region r, K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> {
    Occupied(OccupiedEntry<region r, K, V, A, S>);
    Vacant(VacantEntry<region r, K, V, A, S>)
}

extend<K: Hash + PartialEq, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub mut fn entry(take key: K): Entry<region self, K, V, A, S> {
        match self.find_entry(key) {
            present(index) => Entry.Occupied(OccupiedEntry(mut self, index)),
            none => Entry.Vacant(VacantEntry(mut self, key))
        }
    }
}

extend<region r, K: Hash + PartialEq, V, A: Allocator, S: BuildHasher> OccupiedEntry<region r, K, V, A, S> {
    pub fn key(): read K from self { read self.map.entries[self.index].key }
    pub fn get(): read V from self { read self.map.entries[self.index].value }
    // The exclusive map loan preserves this initialized index; the returned
    // view cannot outlive this reborrow of the entry.
    pub mut fn get_mut(): mut V from self {
        unsafe { mut (*self.map.entries.as_mut_ptr().add(self.index)).value }
    }
    pub mut fn insert(take value: V): V {
        let slot = unsafe { core.ptr.from_mut((*self.map.entries.as_mut_ptr().add(self.index)).value) }
        unsafe { core.ptr.replace(slot, value) }
    }
    pub take fn into_mut(): mut V from r {
        unsafe { mut (*self.map.entries.as_mut_ptr().add(self.index)).value }
    }
    pub take fn remove(): V {
        self.map.remove_index(self.index).1
    }
}

extend<region r, K: Hash + PartialEq, V, A: Allocator, S: BuildHasher> VacantEntry<region r, K, V, A, S> {
    pub take fn insert(take value: V): mut V from r {
        let slot = self.map.or_insert(self.key, value)
        // The returned pointer is to the inserted value; the exclusive map
        // loan outlives this consumed entry and prevents reallocations.
        let p = core.ptr.from_mut(*slot)
        unsafe { mut *p }
    }
}

extend<region r, K: Hash + PartialEq, V, A: Allocator, S: BuildHasher> Entry<region r, K, V, A, S> {
    pub fn key(): read K from self {
        match self {
            Entry.Occupied(entry) => entry.key(),
            Entry.Vacant(entry) => read entry.key
        }
    }
    pub take fn or_insert(take value: V): mut V from r {
        match take self {
            Entry.Occupied(entry) => entry.into_mut(),
            Entry.Vacant(entry) => entry.insert(value)
        }
    }
    pub take fn or_insert_with<F: take fn(): V>(take make: F): mut V from r {
        match take self {
            Entry.Occupied(entry) => entry.into_mut(),
            Entry.Vacant(entry) => entry.insert(make())
        }
    }
    pub take fn or_insert_with_key<F: take fn(read K): V>(take make: F): mut V from r {
        match take self {
            Entry.Occupied(entry) => entry.into_mut(),
            Entry.Vacant(entry) => {
                let value = make(read entry.key)
                entry.insert(value)
            }
        }
    }
    pub take fn insert_entry(take value: V): OccupiedEntry<region r, K, V, A, S> {
        match take self {
            Entry.Occupied(entry) => {
                var occupied = entry
                let _old = occupied.insert(value)
                occupied
            },
            Entry.Vacant(entry) => {
                let index = entry.map.entries.len()
                let _old = entry.map.insert(entry.key, value)
                OccupiedEntry(entry.map, index)
            }
        }
    }
    pub take fn and_modify<F: take fn(mut V): Unit>(take modify: F): Entry<region r, K, V, A, S> {
        match take self {
            Entry.Occupied(entry) => {
                var occupied = entry
                modify(occupied.get_mut())
                Entry.Occupied(occupied)
            },
            Entry.Vacant(entry) => Entry.Vacant(entry)
        }
    }
}

extend<region r, K: Hash + PartialEq, V: Default, A: Allocator, S: BuildHasher> Entry<region r, K, V, A, S> {
    pub take fn or_default(): mut V from r {
        self.or_insert_with(take fn(): V { V.(Default).default() })
    }
}

extend<region r, K: Hash + PartialEq + fmt.Debug, V: fmt.Debug, A: Allocator, S: BuildHasher> Entry<region r, K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        match self {
            Entry.Occupied(entry) => {
                try f.write_str("Occupied(")
                try K.(fmt.Debug).fmt(entry.key(), mut f)
                try f.write_str(": ")
                try V.(fmt.Debug).fmt(entry.get(), mut f)
                try f.write_str(")")
            },
            Entry.Vacant(entry) => {
                try f.write_str("Vacant(")
                try K.(fmt.Debug).fmt(entry.key, mut f)
                try f.write_str(")")
            }
        }
    }
}
