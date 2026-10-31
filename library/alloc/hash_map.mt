import package.core.iter.{Iterator, BidirectionalIterator, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems}
import package.core.clone.Clone
import package.core.default.Default
import package.core.cmp.Eq
import package.core.fmt
import package.core.slice.SliceIter
import super.alloc.{Allocator, Global, AllocError, Layout, layout_unchecked, handle_alloc_error, layout_of}
import package.core.hash.{Hash, hash_one}
import super.vec.List
import package.core.cmp.PartialEq
import package.core.borrow.KeyView

fn empty(): usize { 0xffffffffffffffffusize }

pub type Bucket<K, V> {
    pub hash: u64
    pub key: K
    pub value: V
}

// Entries live densely in a `List` and a power-of-two index table (linear
// probing, backward-shift deletion) maps hashes to entry positions. Both
// blocks come from the same allocator; iteration order is unspecified.
pub type Map<K, V, A: Allocator = Global> {
    entries: List<Bucket<K, V>, A>
    idx: ptr<mut usize>
    icap: usize
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
            present(entry) => present((entry.key, entry.value)),
            none => none
        }
    }
}
extend<region r, K, V, A: Allocator> MapDrain<region r, K, V, A> implements BidirectionalIterator {
    mut fn next_back(): (K, V)? {
        match take self.inner.next_back() {
            present(entry) => present((entry.key, entry.value)),
            none => none
        }
    }
}

pub type ExtractIf<region r, K, V, A: Allocator, F> {
    map: mut Map<K, V, A> from r
    predicate: F
    index: usize
}
extend<region r, K: Hash + PartialEq, V, A: Allocator, F: fn(read K, mut V): bool> ExtractIf<region r, K, V, A, F> implements Iterator {
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

pub fn new_in<K, V, A: Allocator>(a: take A): Map<K, V, A> {
    Map<K, V, A>(allocator: take a)
}
pub fn new<K, V>(): Map<K, V> { new_in(Global()) }

extend<K, V> Map<K, V> {
    pub init() {
        self.entries = super.vec.new<Bucket<K, V>>()
        self.idx = core.ptr.null_mut<usize>()
        self.icap = 0usize
    }
}

extend<K, V, A: Allocator> Map<K, V, A> {
    pub init(allocator: take A) {
        self.entries = super.vec.new_in<Bucket<K, V>, A>(take allocator)
        self.idx = core.ptr.null_mut<usize>()
        self.icap = 0usize
    }
}

fn hash_of<Q: Hash + unsized>(k: read Q): u64 { hash_one(k) }

extend<K: Hash + PartialEq, V, A: Allocator> Map<K, V, A> {
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
    fn find_pos<Q: PartialEq + unsized>(hash: u64, key: read Q): usize? where K: KeyView<Q> {
        if self.icap == 0usize { return none }
        let mask = self.icap - 1usize
        var pos = (hash as usize) & mask
        while true {
            let s = self.slot(pos)
            if s == empty() { return none }
            let hit = match self.entries.get(s) {
                present(e) => e.hash == hash && e.key.key_view().eq(key),
                none => false
            }
            if hit { return present(pos) }
            pos = (pos + 1usize) & mask
        }
        none
    }
    fn find_entry<Q: Hash + PartialEq + unsized>(key: read Q): usize? where K: KeyView<Q> {
        let hash = hash_of(key)
        match self.find_pos(hash, key) {
            present(pos) => present(self.slot(pos)),
            none => none
        }
    }

    // Reindexes into a fresh table of `ncap` slots; failure changes nothing.
    mut fn rebuild(ncap: usize): Unit throws AllocError {
        let bytes = match ncap.checked_mul(8usize) {
            present(b) => b,
            none => throw AllocError(empty(), 8usize)
        }
        if bytes > 0x7fffffffffffffffusize - 7usize {
            throw AllocError(bytes, 8usize)
        }
        let layout = unsafe { layout_unchecked(bytes, 8usize) }
        let np = try self.entries.allocator_mut().allocate(layout)
        let nidx = np.cast<usize>()
        var i = 0usize
        while i < ncap {
            unsafe { *nidx.add(i) = empty() }
            i += 1usize
        }
        if self.icap != 0usize {
            let old = unsafe { layout_unchecked(self.icap * 8usize, 8usize) }
            unsafe { self.entries.allocator_mut().deallocate(self.idx.cast<u8>(), old) }
        }
        self.idx = nidx
        self.icap = ncap
        let mask = ncap - 1usize
        var e = 0usize
        while e < self.entries.len() {
            let h = match self.entries.get(e) { present(b) => b.hash, none => 0u64 }
            var pos = (h as usize) & mask
            while self.slot(pos) != empty() { pos = (pos + 1usize) & mask }
            self.set_slot(pos, e)
            e += 1usize
        }
    }

    pub mut fn try_reserve(extra: usize): Unit throws AllocError {
        let need = match (self.entries.len()).checked_add(extra) {
            present(n) => n,
            none => throw AllocError(empty(), 8usize)
        }
        try self.entries.try_reserve(extra)
        if need <= self.capacity() { return () }
        var ncap = if self.icap == 0usize { 8usize } else { self.icap }
        while need > ncap - ncap / 4usize {
            if ncap > 0x7fffffffffffffffusize / 2usize {
                throw AllocError(empty(), 8usize)
            }
            ncap *= 2usize
        }
        if ncap != self.icap { try self.rebuild(ncap) }
    }
    pub mut fn try_reserve_exact(extra: usize): Unit throws AllocError {
        let need = match self.entries.len().checked_add(extra) {
            present(n) => n,
            none => throw AllocError(empty(), 8usize)
        }
        try self.entries.try_reserve_exact(extra)
        if need <= self.capacity() { return () }
        var ncap = 8usize
        while need > ncap - ncap / 4usize {
            if ncap > 0x7fffffffffffffffusize / 2usize {
                throw AllocError(empty(), 8usize)
            }
            ncap *= 2usize
        }
        if ncap > self.icap { try self.rebuild(ncap) }
    }
    pub mut fn reserve(extra: usize): Unit {
        match capture self.try_reserve(extra) {
            success(_) => (),
            failure(_) => handle_alloc_error(layout_of<Bucket<K, V>>())
        }
    }
    pub mut fn reserve_exact(extra: usize): Unit {
        match capture self.try_reserve_exact(extra) {
            success(_) => (),
            failure(_) => handle_alloc_error(layout_of<Bucket<K, V>>())
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
            unsafe {
                self.entries.allocator_mut().deallocate(self.idx.cast<u8>(), old)
            }
            self.idx = core.ptr.null_mut<usize>()
            self.icap = 0usize
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
                if target > 0x7fffffffffffffffusize / 2usize { return () }
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
        self.entries.shrink_to_fit()
        if self.entries.capacity() < min_capacity {
            self.entries.reserve(min_capacity - self.entries.len())
        }
    }

    // Lookups take a borrowed query `Q` that the stored key views as (a
    // `String` key is searched with a `Text`); equal keys and queries must hash
    // alike (see `KeyView`).
    pub fn contains_key<Q: Hash + PartialEq + unsized>(key: read Q): bool where K: KeyView<Q> {
        match self.find_entry(key) { present(_) => true, none => false }
    }
    pub fn get<Q: Hash + PartialEq + unsized>(key: read Q): (read V from self)? where K: KeyView<Q> {
        match self.find_entry(key) {
            present(s) => match self.entries.get(s) { present(e) => present(read e.value), none => none },
            none => none
        }
    }
    pub fn get_key_value<Q: Hash + PartialEq + unsized>(key: read Q): (read K from self, read V from self)? where K: KeyView<Q> {
        match self.find_entry(key) {
            present(s) => match self.entries.get(s) {
                present(e) => present((read e.key, read e.value)),
                none => none
            },
            none => none
        }
    }
    pub mut fn get_mut<Q: Hash + PartialEq + unsized>(key: read Q): (mut V from self)? where K: KeyView<Q> {
        match self.find_entry(key) {
            present(s) => present(unsafe { mut (*self.entries.as_mut_ptr().add(s)).value }),
            none => none
        }
    }
    pub mut fn get_disjoint_mut<Q: Hash + PartialEq + unsized, R: Hash + PartialEq + unsized>(
        first: read Q,
        second: read R
    ): (mut V from self, mut V from self)? where K: KeyView<Q> + KeyView<R> {
        let first_index = self.find_entry(first)
        let second_index = self.find_entry(second)
        match first_index {
            present(i) => match second_index {
                present(j) => {
                    if i == j { return none }
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
    pub mut unsafe fn get_disjoint_unchecked_mut<Q: Hash + PartialEq + unsized, R: Hash + PartialEq + unsized>(
        first: read Q,
        second: read R
    ): (mut V from self, mut V from self) where K: KeyView<Q> + KeyView<R> {
        let i = match self.find_entry(first) {
            present(index) => index,
            none => package.core.panic.unreachable()
        }
        let j = match self.find_entry(second) {
            present(index) => index,
            none => package.core.panic.unreachable()
        }
        if i == j { package.core.panic.unreachable() }
        let entries = self.entries.as_mut_ptr()
        (mut (*entries.add(i)).value, mut (*entries.add(j)).value)
    }
    pub mut fn extract_if<F: fn(read K, mut V): bool>(
        predicate: take F
    ): ExtractIf<region self, K, V, A, F> {
        ExtractIf(mut self, predicate, 0usize)
    }

    // Inserts or replaces; a replaced value is returned. On allocation failure
    // the map is unchanged and the pair is dropped.
    pub mut fn try_insert(key: take K, value: take V): V? throws AllocError {
        let hash = hash_of(key)
        match self.find_pos(hash, key) {
            present(pos) => {
                let s = self.slot(pos)
                let slot = unsafe { core.ptr.from_mut((*self.entries.as_mut_ptr().add(s)).value) }
                return present(unsafe { core.ptr.replace(slot, value) })
            },
            none => {}
        }
        try self.try_reserve(1usize)
        let at = self.entries.len()
        self.entries.push(Bucket(hash, key, value))
        let mask = self.icap - 1usize
        var pos = (hash as usize) & mask
        while self.slot(pos) != empty() { pos = (pos + 1usize) & mask }
        self.set_slot(pos, at)
        none
    }
    pub mut fn insert(key: take K, value: take V): V? {
        let outcome = capture self.try_insert(key, value)
        match take outcome {
            success(old) => old,
            failure(_) => handle_alloc_error(layout_of<Bucket<K, V>>())
        }
    }

    // Returns the value for `key`, inserting `value` first when absent.
    pub mut fn or_insert(key: take K, value: take V): mut V from self {
        let found = self.find_entry(key)
        let s = match found {
            present(s) => s,
            none => {
                let r = self.insert(key, value)
                self.entries.len() - 1usize
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
            none => package.core.panic.unreachable()
        }
        let mask = self.icap - 1usize
        var pos = (hash as usize) & mask
        while self.slot(pos) != s {
            if self.slot(pos) == empty() { package.core.panic.unreachable() }
            pos = (pos + 1usize) & mask
        }
        self.remove_at(s, pos)
    }
    pub mut fn remove_entry<Q: Hash + PartialEq + unsized>(key: read Q): (K, V)? where K: KeyView<Q> {
        let hash = hash_of(key)
        let pos = match self.find_pos(hash, key) { present(p) => p, none => { return none } }
        let s = self.slot(pos)
        present(self.remove_at(s, pos))
    }
    pub mut fn remove<Q: Hash + PartialEq + unsized>(key: read Q): V? where K: KeyView<Q> {
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
        MapDrain(self.entries.drain(0usize, count))
    }
}

// Set of keys backed by a map with unit values.
pub type Set<K, A: Allocator = Global> { map: Map<K, Unit, A> }

fn set_from_map<K, A: Allocator>(map: take Map<K, Unit, A>): Set<K, A> {
    let result: Set<K, A>
    result.map = take map
    result
}

pub fn set_new_in<K, A: Allocator>(a: take A): Set<K, A> {
    Set<K, A>(allocator: take a)
}
pub fn set_new<K>(): Set<K> { Set<K>() }

extend<K> Set<K> {
    pub init() { self.map = new<K, Unit>() }
}

extend<K, A: Allocator> Set<K, A> {
    pub init(allocator: take A) {
        self.map = new_in<K, Unit, A>(take allocator)
    }
}

extend<K: Hash + PartialEq, A: Allocator> Set<K, A> {
    pub fn len(): usize { self.map.len() }
    pub fn capacity(): usize { self.map.capacity() }
    pub fn is_empty(): bool { self.map.is_empty() }
    pub mut fn try_reserve(extra: usize): Unit throws AllocError {
        try self.map.try_reserve(extra)
    }
    pub mut fn try_reserve_exact(extra: usize): Unit throws AllocError {
        try self.map.try_reserve_exact(extra)
    }
    pub mut fn reserve(extra: usize): Unit { self.map.reserve(extra) }
    pub mut fn reserve_exact(extra: usize): Unit { self.map.reserve_exact(extra) }
    pub mut fn shrink_to_fit(): Unit { self.map.shrink_to_fit() }
    pub mut fn shrink_to(min_capacity: usize): Unit { self.map.shrink_to(min_capacity) }
    pub fn contains<Q: Hash + PartialEq + unsized>(key: read Q): bool where K: KeyView<Q> { self.map.contains_key(key) }
    pub fn get<Q: Hash + PartialEq + unsized>(key: read Q): (read K from self)? where K: KeyView<Q> {
        match self.map.find_entry(key) {
            present(index) => match self.map.entries.get(index) {
                present(entry) => present(read entry.key),
                none => none
            },
            none => none
        }
    }
    // True when the key was newly added.
    pub mut fn insert(key: take K): bool {
        match self.map.insert(key, ()) { present(_) => false, none => true }
    }
    pub mut fn try_insert(key: take K): bool throws AllocError {
        match try self.map.try_insert(key, ()) { present(_) => false, none => true }
    }
    pub mut fn remove<Q: Hash + PartialEq + unsized>(key: read Q): bool where K: KeyView<Q> {
        match self.map.remove(key) { present(_) => true, none => false }
    }
    pub mut fn `take`<Q: Hash + PartialEq + unsized>(key: read Q): K? where K: KeyView<Q> {
        match take self.map.remove_entry(key) {
            present(entry) => present(entry.0),
            none => none
        }
    }
    pub mut fn clear(): Unit { self.map.clear() }
    pub fn as_entries(): read [Bucket<K, Unit>] from self { self.map.as_entries() }
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
}
extend<region r, K, A: Allocator> SetDrain<region r, K, A> implements BidirectionalIterator {
    mut fn next_back(): K? {
        match take self.inner.next_back() {
            present(entry) => present(entry.0),
            none => none
        }
    }
}

pub type SetExtractIf<region r, K, A: Allocator, F> {
    set: mut Set<K, A> from r
    predicate: F
    index: usize
}
extend<region r, K: Hash + PartialEq, A: Allocator, F: fn(read K): bool> SetExtractIf<region r, K, A, F> implements Iterator {
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
pub type SetAlgebra<region r, K, A: Allocator> {
    left: read Set<K, A> from r
    right: read Set<K, A> from r
    mode: u8
    side: u8
    index: usize
}
extend<region r, K: Hash + PartialEq, A: Allocator> SetAlgebra<region r, K, A> implements Iterator {
    type Item = read K from r
    mut fn next(): (read K from r)? {
        while self.side < 2u8 {
            if self.mode == 1u8 && self.side == 1u8 { return none }
            if self.side == 0u8 {
                if self.index >= self.left.map.entries.len() {
                    self.side = 1u8
                    self.index = 0usize
                    continue
                }
                let i = self.index
                self.index += 1usize
                let key = read self.left.map.entries[i].key
                let in_right = match self.right.map.find_entry(key) {
                    present(_) => true,
                    none => false
                }
                let include = match self.mode {
                    0u8 => true,
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

extend<K: Hash + PartialEq, A: Allocator> Set<K, A> {
    pub fn `union`(other: read Set<K, A> from self): SetAlgebra<region self, K, A> {
        SetAlgebra(read self, other, 0u8, 0u8, 0usize)
    }
    pub fn intersection(other: read Set<K, A> from self): SetAlgebra<region self, K, A> {
        SetAlgebra(read self, other, 1u8, 0u8, 0usize)
    }
    pub fn difference(other: read Set<K, A> from self): SetAlgebra<region self, K, A> {
        SetAlgebra(read self, other, 2u8, 0u8, 0usize)
    }
    pub fn symmetric_difference(other: read Set<K, A> from self): SetAlgebra<region self, K, A> {
        SetAlgebra(read self, other, 3u8, 0u8, 0usize)
    }
    pub fn is_subset(other: read Set<K, A>): bool {
        var i = 0usize
        while i < self.map.entries.len() {
            if !other.contains(self.map.entries[i].key) { return false }
            i += 1usize
        }
        true
    }
    pub fn is_superset(other: read Set<K, A>): bool {
        var i = 0usize
        while i < other.map.entries.len() {
            if !self.contains(other.map.entries[i].key) { return false }
            i += 1usize
        }
        true
    }
    pub fn is_disjoint(other: read Set<K, A>): bool {
        var i = 0usize
        while i < self.map.entries.len() {
            if other.contains(self.map.entries[i].key) { return false }
            i += 1usize
        }
        true
    }
    pub mut fn drain(): SetDrain<region self, K, A> { SetDrain(self.map.drain()) }
    pub mut fn extract_if<F: fn(read K): bool>(
        predicate: take F
    ): SetExtractIf<region self, K, A, F> {
        SetExtractIf(mut self, predicate, 0usize)
    }
}


// Iteration is in insertion order and yields the stored buckets; keys are not
// mutably iterable because that could break the table's hash invariants.
extend<K, V, A: Allocator> Map<K, V, A> implements Iterable {
    type Item = Bucket<K, V>
    type Iter<region r> = SliceIter<region r, Bucket<K, V>>
    fn iter<region r>(receiver self: read Self from r): SliceIter<region r, Bucket<K, V>> { self.entries.as_slice().iter() }
}
extend<K, A: Allocator> Set<K, A> implements Iterable {
    type Item = Bucket<K, Unit>
    type Iter<region r> = SliceIter<region r, Bucket<K, Unit>>
    fn iter<region r>(receiver self: read Self from r): SliceIter<region r, Bucket<K, Unit>> { self.map.entries.as_slice().iter() }
}

// Consuming iteration moves out entries without consulting the now-stale
// index; dropping the iterator releases the remaining buckets and index block.
pub type MapIntoIter<K, V, A: Allocator = Global> { map: Map<K, V, A> }
extend<K, V, A: Allocator> MapIntoIter<K, V, A> implements Iterator {
    type Item = (K, V)
    mut fn next(): (K, V)? {
        match take self.map.entries.pop() {
            present(entry) => present((entry.key, entry.value)),
            none => none
        }
    }
}
extend<K, V, A: Allocator> Map<K, V, A> implements OwnedIterable {
    type Item = (K, V)
    type IntoIter = MapIntoIter<K, V, A>
    fn into_iter(receiver self: take Self): MapIntoIter<K, V, A> {
        MapIntoIter(take self)
    }
}

extend<K: Hash + PartialEq, V, A: Allocator> Map<K, V, A> {
    pub take fn into_keys(): IntoKeys<K, V, A> { IntoKeys(self.into_iter()) }
    pub take fn into_values(): IntoValues<K, V, A> { IntoValues(self.into_iter()) }
}
pub type IntoKeys<K, V, A: Allocator> { inner: MapIntoIter<K, V, A> }
extend<K, V, A: Allocator> IntoKeys<K, V, A> implements Iterator {
    type Item = K
    mut fn next(): K? {
        match take self.inner.next() {
            present(entry) => present(entry.0),
            none => none
        }
    }
}
pub type IntoValues<K, V, A: Allocator> { inner: MapIntoIter<K, V, A> }
extend<K, V, A: Allocator> IntoValues<K, V, A> implements Iterator {
    type Item = V
    mut fn next(): V? {
        match take self.inner.next() {
            present(entry) => present(entry.1),
            none => none
        }
    }
}

pub type SetIntoIter<K, A: Allocator = Global> { inner: MapIntoIter<K, Unit, A> }
extend<K, A: Allocator> SetIntoIter<K, A> implements Iterator {
    type Item = K
    mut fn next(): K? {
        match take self.inner.next() {
            present(pair) => present(pair.0),
            none => none
        }
    }
}
extend<K, A: Allocator> Set<K, A> implements OwnedIterable {
    type Item = K
    type IntoIter = SetIntoIter<K, A>
    fn into_iter(receiver self: take Self): SetIntoIter<K, A> {
        SetIntoIter(self.map.into_iter())
    }
}

// Mutable iteration visits the values only: mutable keys could break the table's hash invariants.
pub type ValuesMut<region r, K, V, A: Allocator> { map: mut Map<K, V, A> from r; index: usize }
extend<region r, K, V, A: Allocator> ValuesMut<region r, K, V, A> implements Iterator {
    type Item = mut V from r
    mut fn next(): (mut V from r)? {
        if self.index < self.map.entries.len() {
            let i = self.index
            self.index += 1usize
            present(unsafe { mut (*self.map.entries.as_mut_ptr().add(i)).value })
        } else {
            none
        }
    }
}
// Borrowed iterators over the keys or the values only.
pub type Keys<region r, K, V> { inner: SliceIter<region r, Bucket<K, V>> }
extend<region r, K, V> Keys<region r, K, V> implements Iterator {
    type Item = read K from r
    mut fn next(): (read K from r)? {
        match self.inner.next() { present(e) => present(read e.key), none => none }
    }
}
pub type Values<region r, K, V> { inner: SliceIter<region r, Bucket<K, V>> }
extend<region r, K, V> Values<region r, K, V> implements Iterator {
    type Item = read V from r
    mut fn next(): (read V from r)? {
        match self.inner.next() { present(e) => present(read e.value), none => none }
    }
}
extend<K, V, A: Allocator> Map<K, V, A> {
    pub fn keys(): Keys<region self, K, V> { Keys(self.entries.as_slice().iter()) }
    pub fn values(): Values<region self, K, V> { Values(self.entries.as_slice().iter()) }
}
extend<K, V, A: Allocator> Map<K, V, A> implements MutableIterable {
    type Item = V
    type IterMut<region r> = ValuesMut<region r, K, V, A>
    fn iter_mut<region r>(receiver self: mut Self from r): ValuesMut<region r, K, V, A> { ValuesMut(mut self, 0usize) }
}
extend<K, V, A: Allocator> Map<K, V, A> {
    pub mut fn values_mut(): ValuesMut<region self, K, V, A> { ValuesMut(mut self, 0usize) }
}

extend<K: Hash + PartialEq + Clone, V: Clone, A: Allocator + Clone> Map<K, V, A> implements Clone {
    fn clone(): Map<K, V, A> {
        var out = new_in<K, V, A>(self.entries.allocator().clone())
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
extend<K: Hash + PartialEq, V: PartialEq, A: Allocator> Map<K, V, A> implements PartialEq {
    fn eq(other: read Map<K, V, A>): bool {
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
extend<K: Hash + PartialEq, V: Eq, A: Allocator> Map<K, V, A> implements Eq {}
extend<K: fmt.Debug, V: fmt.Debug, A: Allocator> Map<K, V, A> implements fmt.Debug {
    fn fmt<W: fmt.Write>(f: mut fmt.Formatter<W>): Unit throws fmt.Error {
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
extend<K: Hash + PartialEq, V, A: Allocator> Map<K, V, A> implements ExtendItems<(K, V)> {
    mut fn extend<I: OwnedIterable<Item = (K, V)>>(items: take I): Unit {
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
    static fn from_iter<I: OwnedIterable<Item = (K, V)>>(items: take I): Map<K, V> {
        var out = new<K, V>()
        out.extend(items)
        out
    }
}

extend<K: Hash + PartialEq + Clone, A: Allocator + Clone> Set<K, A> implements Clone {
    fn clone(): Set<K, A> { set_from_map(self.map.clone()) }
}
// Equal when both hold the same elements, in any order.
extend<K: Hash + PartialEq, A: Allocator> Set<K, A> implements PartialEq {
    fn eq(other: read Set<K, A>): bool {
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
extend<K: Hash + PartialEq, A: Allocator> Set<K, A> implements Eq {}
extend<K: fmt.Debug, A: Allocator> Set<K, A> implements fmt.Debug {
    fn fmt<W: fmt.Write>(f: mut fmt.Formatter<W>): Unit throws fmt.Error {
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
extend<K: Hash + PartialEq, A: Allocator> Set<K, A> implements ExtendItems<K> {
    mut fn extend<I: OwnedIterable<Item = K>>(items: take I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { let added = self.insert(item) }, none => { break } }
        }
    }
}
extend<K: Hash + PartialEq> Set<K> implements FromItems<K> {
    static fn from_iter<I: OwnedIterable<Item = K>>(items: take I): Set<K> {
        var out = set_new<K>()
        out.extend(items)
        out
    }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<K: Transferable, V: Transferable, A: Allocator + Transferable> Map<K, V, A> implements Transferable {}
unsafe extend<K: Shareable, V: Shareable, A: Allocator + Shareable> Map<K, V, A> implements Shareable {}

// An entry owns the query key and exclusively borrows its map until consumed.
// The occupied index remains valid because the loan excludes map mutation.
pub type OccupiedEntry<region r, K, V, A: Allocator = Global> {
    map: mut Map<K, V, A> from r
    index: usize
}
pub type VacantEntry<region r, K, V, A: Allocator = Global> {
    map: mut Map<K, V, A> from r
    key: K
}
pub enum Entry<region r, K, V, A: Allocator = Global> {
    Occupied(OccupiedEntry<region r, K, V, A>);
    Vacant(VacantEntry<region r, K, V, A>)
}

extend<K: Hash + PartialEq, V, A: Allocator> Map<K, V, A> {
    pub mut fn entry(key: take K): Entry<region self, K, V, A> {
        match self.find_entry(key) {
            present(index) => Entry.Occupied(OccupiedEntry(mut self, index)),
            none => Entry.Vacant(VacantEntry(mut self, key))
        }
    }
}

extend<region r, K: Hash + PartialEq, V, A: Allocator> OccupiedEntry<region r, K, V, A> {
    pub fn key(): read K from self { read self.map.entries[self.index].key }
    pub fn get(): read V from self { read self.map.entries[self.index].value }
    // The exclusive map loan preserves this initialized index; the returned
    // view cannot outlive this reborrow of the entry.
    pub mut fn get_mut(): mut V from self {
        unsafe { mut (*self.map.entries.as_mut_ptr().add(self.index)).value }
    }
    pub mut fn insert(value: take V): V {
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

extend<region r, K: Hash + PartialEq, V, A: Allocator> VacantEntry<region r, K, V, A> {
    pub take fn insert(value: take V): mut V from r {
        let slot = self.map.or_insert(self.key, value)
        // The returned pointer is to the inserted value; the exclusive map
        // loan outlives this consumed entry and prevents reallocations.
        let p = core.ptr.from_mut(*slot)
        unsafe { mut *p }
    }
}

extend<region r, K: Hash + PartialEq, V, A: Allocator> Entry<region r, K, V, A> {
    pub take fn or_insert(value: take V): mut V from r {
        match take self {
            Entry.Occupied(entry) => entry.into_mut(),
            Entry.Vacant(entry) => entry.insert(value)
        }
    }
    pub take fn or_insert_with<F: take fn(): V>(make: take F): mut V from r {
        match take self {
            Entry.Occupied(entry) => entry.into_mut(),
            Entry.Vacant(entry) => entry.insert(make())
        }
    }
    pub take fn or_insert_with_key<F: take fn(read K): V>(make: take F): mut V from r {
        match take self {
            Entry.Occupied(entry) => entry.into_mut(),
            Entry.Vacant(entry) => entry.insert(make(read entry.key))
        }
    }
    pub take fn insert_entry(value: take V): OccupiedEntry<region r, K, V, A> {
        match take self {
            Entry.Occupied(entry) => {
                let _old = entry.insert(value)
                entry
            },
            Entry.Vacant(entry) => {
                let index = entry.map.entries.len()
                let _old = entry.map.insert(entry.key, value)
                OccupiedEntry(mut entry.map, index)
            }
        }
    }
    pub take fn and_modify<F: take fn(mut V): Unit>(modify: take F): Entry<region r, K, V, A> {
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

extend<region r, K: Hash + PartialEq, V: Default, A: Allocator> Entry<region r, K, V, A> {
    pub take fn or_default(): mut V from r {
        self.or_insert_with(take fn(): V { V.(Default).default() })
    }
}
