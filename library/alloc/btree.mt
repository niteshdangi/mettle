import package.core.iter.{Iterator, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems}
import package.core.clone.Clone
import package.core.cmp.{Eq, PartialEq, PartialOrd}
import package.core.hash.{Hash, Hasher}
import package.core.fmt
import package.core.slice.SliceIter
import super.alloc.{Allocator, Global, AllocError}
import super.vec.List
import package.core.cmp.{Ord, Ordering}
import package.core.borrow.KeyView

pub type Entry<K, V> {
    pub key: K
    pub value: V
}

// Ordered map kept as a sorted array: lookups are O(log n) binary searches,
// updates move O(n) entries. It provides the ordered-iteration and range
// contract of `SortedMap`; a node-based B-tree is future work.
pub type SortedMap<K, V, A: Allocator = Global> {
    entries: List<Entry<K, V>, A>
}

pub fn new_in<K, V, A: Allocator>(a: take A): SortedMap<K, V, A> {
    SortedMap(super.vec.new_in<Entry<K, V>, A>(a))
}
pub fn new<K, V>(): SortedMap<K, V> { new_in(Global()) }

extend<K: Ord, V, A: Allocator> SortedMap<K, V, A> {
    pub fn len(): usize { self.entries.len() }
    pub fn is_empty(): bool { self.entries.is_empty() }
    // Entries in ascending key order.
    pub fn as_entries(): read [Entry<K, V>] from self { self.entries.as_slice() }

    // First position whose key is not less than `key`.
    pub fn lower_bound(key: read K): usize {
        var lo = 0usize
        var hi = self.entries.len()
        while lo < hi {
            let mid = lo + (hi - lo) / 2usize
            if self.entries[mid].key.cmp(key).is_lt() { lo = mid + 1usize } else { hi = mid }
        }
        lo
    }
    // First position whose key is greater than `key`.
    pub fn upper_bound(key: read K): usize {
        var lo = 0usize
        var hi = self.entries.len()
        while lo < hi {
            let mid = lo + (hi - lo) / 2usize
            if key.cmp(self.entries[mid].key).is_lt() { hi = mid } else { lo = mid + 1usize }
        }
        lo
    }
    // Positions of the half-open key range `[from, to)` as `(start, end)`.
    pub fn range(from: read K, to: read K): (usize, usize) {
        let start = self.lower_bound(from)
        let end = self.lower_bound(to)
        if end < start { (start, start) } else { (start, end) }
    }
    // Position of the entry whose key views as `key`, by binary search.
    fn position<Q: Ord + unsized>(key: read Q): usize? where K: KeyView<Q> {
        var lo = 0usize
        var hi = self.entries.len()
        while lo < hi {
            let mid = lo + (hi - lo) / 2usize
            if self.entries[mid].key.key_view().cmp(key).is_lt() { lo = mid + 1usize } else { hi = mid }
        }
        if lo < self.entries.len() && self.entries[lo].key.key_view().cmp(key).is_eq() { present(lo) } else { none }
    }
    // Lookups take a borrowed query `Q` that the stored key views as (a
    // `String` key is searched with a `Text`); `Q`'s order must agree with `K`'s.
    pub fn contains_key<Q: Ord + unsized>(key: read Q): bool where K: KeyView<Q> {
        match self.position(key) { present(_) => true, none => false }
    }
    pub fn get<Q: Ord + unsized>(key: read Q): (read V from self)? where K: KeyView<Q> {
        match self.position(key) {
            present(i) => present(unsafe { read (*self.entries.as_ptr().add(i)).value }),
            none => none
        }
    }
    pub mut fn get_mut<Q: Ord + unsized>(key: read Q): (mut V from self)? where K: KeyView<Q> {
        match self.position(key) {
            present(i) => present(unsafe { mut (*self.entries.as_mut_ptr().add(i)).value }),
            none => none
        }
    }
    pub fn first_key(): (read K from self)? {
        if self.entries.is_empty() { return none }
        present(unsafe { read (*self.entries.as_ptr()).key })
    }
    pub fn last_key(): (read K from self)? {
        if self.entries.is_empty() { return none }
        present(unsafe { read (*self.entries.as_ptr().add(self.entries.len() - 1usize)).key })
    }
    pub mut fn try_insert(key: take K, value: take V): V? throws AllocError {
        let i = self.lower_bound(key)
        if i < self.entries.len() && self.entries[i].key.cmp(key).is_eq() {
            let slot = unsafe { core.ptr.from_mut((*self.entries.as_mut_ptr().add(i)).value) }
            return present(unsafe { core.ptr.replace(slot, value) })
        }
        try self.entries.try_reserve(1usize)
        self.entries.insert(i, Entry(key, value))
        none
    }
    pub mut fn insert(key: take K, value: take V): V? {
        let i = self.lower_bound(key)
        if i < self.entries.len() && self.entries[i].key.cmp(key).is_eq() {
            let slot = unsafe { core.ptr.from_mut((*self.entries.as_mut_ptr().add(i)).value) }
            return present(unsafe { core.ptr.replace(slot, value) })
        }
        self.entries.insert(i, Entry(key, value))
        none
    }
    pub mut fn remove<Q: Ord + unsized>(key: read Q): V? where K: KeyView<Q> {
        match self.position(key) {
            present(i) => {
                let e = self.entries.remove(i)
                present(e.value)
            },
            none => none
        }
    }
    pub mut fn clear(): Unit { self.entries.clear() }
}

pub type SortedSet<K, A: Allocator = Global> { map: SortedMap<K, Unit, A> }

pub fn set_new_in<K, A: Allocator>(a: take A): SortedSet<K, A> { SortedSet(new_in<K, Unit, A>(a)) }
pub fn set_new<K>(): SortedSet<K> { SortedSet(new<K, Unit>()) }

extend<K: Ord, A: Allocator> SortedSet<K, A> {
    pub fn len(): usize { self.map.len() }
    pub fn is_empty(): bool { self.map.is_empty() }
    pub fn contains<Q: Ord + unsized>(key: read Q): bool where K: KeyView<Q> { self.map.contains_key(key) }
    pub mut fn insert(key: take K): bool {
        match self.map.insert(key, ()) { present(_) => false, none => true }
    }
    pub mut fn remove<Q: Ord + unsized>(key: read Q): bool where K: KeyView<Q> {
        match self.map.remove(key) { present(_) => true, none => false }
    }
    pub fn first(): (read K from self)? { self.map.first_key() }
    pub fn last(): (read K from self)? { self.map.last_key() }
    pub fn as_entries(): read [Entry<K, Unit>] from self { self.map.as_entries() }
    pub fn range(from: read K, to: read K): (usize, usize) { self.map.range(from, to) }
}


// Iteration is in ascending key order.
extend<K, V, A: Allocator> SortedMap<K, V, A> implements Iterable {
    type Item = Entry<K, V>
    type Iter<region r> = SliceIter<region r, Entry<K, V>>
    fn iter<region r>(receiver self: read Self from r): SliceIter<region r, Entry<K, V>> { self.entries.as_slice().iter() }
}
extend<K, A: Allocator> SortedSet<K, A> implements Iterable {
    type Item = Entry<K, Unit>
    type Iter<region r> = SliceIter<region r, Entry<K, Unit>>
    fn iter<region r>(receiver self: read Self from r): SliceIter<region r, Entry<K, Unit>> { self.map.entries.as_slice().iter() }
}

// Mutable iteration visits the values only, in key order: mutable keys could break the ordering.
pub type ValuesMut<region r, K, V, A: Allocator> { map: mut SortedMap<K, V, A> from r; index: usize }
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
pub type Keys<region r, K, V> { inner: SliceIter<region r, Entry<K, V>> }
extend<region r, K, V> Keys<region r, K, V> implements Iterator {
    type Item = read K from r
    mut fn next(): (read K from r)? {
        match self.inner.next() { present(e) => present(read e.key), none => none }
    }
}
pub type Values<region r, K, V> { inner: SliceIter<region r, Entry<K, V>> }
extend<region r, K, V> Values<region r, K, V> implements Iterator {
    type Item = read V from r
    mut fn next(): (read V from r)? {
        match self.inner.next() { present(e) => present(read e.value), none => none }
    }
}
extend<K, V, A: Allocator> SortedMap<K, V, A> {
    pub fn keys(): Keys<region self, K, V> { Keys(self.entries.as_slice().iter()) }
    pub fn values(): Values<region self, K, V> { Values(self.entries.as_slice().iter()) }
}
extend<K, V, A: Allocator> SortedMap<K, V, A> implements MutableIterable {
    type Item = V
    type IterMut<region r> = ValuesMut<region r, K, V, A>
    fn iter_mut<region r>(receiver self: mut Self from r): ValuesMut<region r, K, V, A> { ValuesMut(mut self, 0usize) }
}
extend<K, V, A: Allocator> SortedMap<K, V, A> {
    pub mut fn values_mut(): ValuesMut<region self, K, V, A> { ValuesMut(mut self, 0usize) }
}

extend<K: Clone, V: Clone, A: Allocator + Clone> SortedMap<K, V, A> implements Clone {
    fn clone(): SortedMap<K, V, A> {
        var out = SortedMap(super.vec.new_in<Entry<K, V>, A>(self.entries.allocator().clone()))
        var i = 0usize
        while i < self.entries.len() {
            let e = read self.entries[i]
            out.entries.push(Entry(e.key.clone(), e.value.clone()))
            i += 1usize
        }
        out
    }
}
extend<K: PartialEq, V: PartialEq, A: Allocator> SortedMap<K, V, A> implements PartialEq {
    fn eq(other: read SortedMap<K, V, A>): bool {
        if self.entries.len() != other.entries.len() { return false }
        var i = 0usize
        while i < self.entries.len() {
            let a = read self.entries[i]
            let b = read other.entries[i]
            if !a.key.eq(b.key) || !a.value.eq(b.value) { return false }
            i += 1usize
        }
        true
    }
}
extend<K: Eq, V: Eq, A: Allocator> SortedMap<K, V, A> implements Eq {}
// Lexicographic over `(key, value)` entries in key order.
extend<K: PartialOrd, V: PartialOrd, A: Allocator> SortedMap<K, V, A> implements PartialOrd {
    fn partial_cmp(other: read SortedMap<K, V, A>): Ordering? {
        var i = 0usize
        while i < self.entries.len() && i < other.entries.len() {
            let a = read self.entries[i]
            let b = read other.entries[i]
            match a.key.partial_cmp(b.key) {
                present(o) => { if !o.is_eq() { return present(o) } },
                none => { return none }
            }
            match a.value.partial_cmp(b.value) {
                present(o) => { if !o.is_eq() { return present(o) } },
                none => { return none }
            }
            i += 1usize
        }
        self.entries.len().partial_cmp(other.entries.len())
    }
}
extend<K: Ord, V: Ord, A: Allocator> SortedMap<K, V, A> implements Ord {
    fn cmp(other: read SortedMap<K, V, A>): Ordering {
        var i = 0usize
        while i < self.entries.len() && i < other.entries.len() {
            let a = read self.entries[i]
            let b = read other.entries[i]
            let k = a.key.cmp(b.key)
            if !k.is_eq() { return k }
            let v = a.value.cmp(b.value)
            if !v.is_eq() { return v }
            i += 1usize
        }
        self.entries.len().cmp(other.entries.len())
    }
}
extend<K: Hash, V: Hash, A: Allocator> SortedMap<K, V, A> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit {
        state.write_usize(self.entries.len())
        var i = 0usize
        while i < self.entries.len() {
            let e = read self.entries[i]
            e.key.hash(mut state)
            e.value.hash(mut state)
            i += 1usize
        }
    }
}
extend<K: fmt.Debug, V: fmt.Debug, A: Allocator> SortedMap<K, V, A> implements fmt.Debug {
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
extend<K: Ord, V, A: Allocator> SortedMap<K, V, A> implements ExtendItems<(K, V)> {
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
extend<K: Ord, V> SortedMap<K, V> implements FromItems<(K, V)> {
    static fn from_iter<I: OwnedIterable<Item = (K, V)>>(items: take I): SortedMap<K, V> {
        var out = new<K, V>()
        out.extend(items)
        out
    }
}

extend<K: Clone, A: Allocator + Clone> SortedSet<K, A> implements Clone {
    fn clone(): SortedSet<K, A> { SortedSet(self.map.clone()) }
}
extend<K: PartialEq, A: Allocator> SortedSet<K, A> implements PartialEq {
    fn eq(other: read SortedSet<K, A>): bool { self.map == other.map }
}
extend<K: Eq, A: Allocator> SortedSet<K, A> implements Eq {}
extend<K: PartialOrd, A: Allocator> SortedSet<K, A> implements PartialOrd {
    fn partial_cmp(other: read SortedSet<K, A>): Ordering? { self.map.partial_cmp(other.map) }
}
extend<K: Ord, A: Allocator> SortedSet<K, A> implements Ord {
    fn cmp(other: read SortedSet<K, A>): Ordering { self.map.cmp(other.map) }
}
extend<K: Hash, A: Allocator> SortedSet<K, A> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.map.hash(mut state) }
}
extend<K: fmt.Debug, A: Allocator> SortedSet<K, A> implements fmt.Debug {
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
extend<K: Ord, A: Allocator> SortedSet<K, A> implements ExtendItems<K> {
    mut fn extend<I: OwnedIterable<Item = K>>(items: take I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { let added = self.insert(item) }, none => { break } }
        }
    }
}
extend<K: Ord> SortedSet<K> implements FromItems<K> {
    static fn from_iter<I: OwnedIterable<Item = K>>(items: take I): SortedSet<K> {
        var out = set_new<K>()
        out.extend(items)
        out
    }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<K: Transferable, V: Transferable, A: Allocator + Transferable> SortedMap<K, V, A> implements Transferable {}
unsafe extend<K: Shareable, V: Shareable, A: Allocator + Shareable> SortedMap<K, V, A> implements Shareable {}
