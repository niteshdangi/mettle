import package.core.iter.{Iterator, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems}
import package.core.clone.Clone
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

// Insertion-ordered open-addressing table: entries live densely in a `List`
// and a power-of-two index table (linear probing, backward-shift deletion)
// maps hashes to entry positions. Both blocks come from the same allocator.
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
    pub fn capacity(): usize { self.icap / 4usize * 3usize }
    pub fn allocator(): read A from self { self.entries.allocator() }
    // Entries in insertion order (removal moves the last entry into the hole).
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
        var ncap = if self.icap == 0usize { 8usize } else { self.icap }
        while need * 4usize > ncap * 3usize { ncap *= 2usize }
        if ncap != self.icap { try self.rebuild(ncap) }
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
    pub mut fn get_mut<Q: Hash + PartialEq + unsized>(key: read Q): (mut V from self)? where K: KeyView<Q> {
        match self.find_entry(key) {
            present(s) => present(unsafe { mut (*self.entries.as_mut_ptr().add(s)).value }),
            none => none
        }
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

    pub mut fn remove<Q: Hash + PartialEq + unsized>(key: read Q): V? where K: KeyView<Q> {
        let hash = hash_of(key)
        let pos = match self.find_pos(hash, key) { present(p) => p, none => { return none } }
        let s = self.slot(pos)
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
        present(b.value)
    }

    pub mut fn clear(): Unit {
        var i = 0usize
        while i < self.icap {
            self.set_slot(i, empty())
            i += 1usize
        }
        self.entries.clear()
    }
}

// Set of keys backed by a map with unit values.
pub type Set<K, A: Allocator = Global> { map: Map<K, Unit, A> }

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
    init(map: take Map<K, Unit, A>, marker: bool) {
        self.map = take map
    }
}

extend<K: Hash + PartialEq, A: Allocator> Set<K, A> {
    pub fn len(): usize { self.map.len() }
    pub fn is_empty(): bool { self.map.is_empty() }
    pub fn contains<Q: Hash + PartialEq + unsized>(key: read Q): bool where K: KeyView<Q> { self.map.contains_key(key) }
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
    pub mut fn clear(): Unit { self.map.clear() }
    pub fn as_entries(): read [Bucket<K, Unit>] from self { self.map.as_entries() }
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
    fn clone(): Set<K, A> { Set<K, A>(self.map.clone(), true) }
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
