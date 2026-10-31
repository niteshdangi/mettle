import package.core.iter.{Iterator, BidirectionalIterator, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems}
import package.core.clone.Clone
import package.core.default.Default
import package.core.cmp.{Eq, PartialEq, PartialOrd}
import package.core.hash.{Hash, Hasher}
import package.core.fmt
import super.alloc.{Allocator, Global, AllocError, layout_unchecked, layout_of, handle_alloc_error, dangling_for}
import package.core.cmp.{Ord, Ordering}
import package.core.borrow.KeyView

pub type Bucket<K, V> {
    pub key: K
    pub value: V
}

// Ordered map stored as a B-tree of minimum degree 6: every node except the
// root holds 5 to 11 entries, an internal node with `n` entries has `n + 1`
// children, and all leaves are at the same depth. Lookups, insertions and
// removals are O(log n); insertion splits full nodes on the way down and
// removal borrows from or merges with a sibling on the way back up.
//
// Storage invariants (every `unsafe` block in this file relies on them):
// - `root` is null exactly when `len == 0`; otherwise it is a live node with
//   no parent, and `len` counts the entries of the whole tree.
// - A node is three blocks from the map's allocator: a header (`Node`), room
//   for `max_entries()` entries and, for an internal node, room for
//   `max_entries() + 1` child links. Slots below `len` (children: `len + 1`)
//   are initialized, the rest are uninitialized and never read or dropped.
// - `parent` of every non-root node points at the node holding its link, so
//   `set_child` is the only way a link is stored. Positions inside a parent
//   are found by scanning its links, never cached.
// - Nodes are owned only by the tree. Raw node pointers handed to helpers
//   below are always live nodes of one tree whose structure is not being
//   modified concurrently; iterators keep the map borrowed (or owned).
// - Entries are moved bitwise between slots; the source slot is afterwards
//   treated as uninitialized, so each entry is dropped exactly once.
type Node<K, V> {
    entries: ptr<mut Bucket<K, V>>
    children: ptr<mut ptr<mut Node<K, V>>>
    parent: ptr<mut Node<K, V>>
    len: usize
    leaf: bool
}

fn max_entries(): usize { 11usize }
fn min_entries(): usize { 5usize }

pub type SortedMap<K, V, A: Allocator = Global> {
    root: ptr<mut Node<K, V>>
    len: usize
    a: A
    // Panics are runtime traps without unwinding or catch; cleanup cannot
    // continue after a destructor traps.
    drop {
        let root = self.root
        self.root = null_node<K, V>()
        self.len = 0usize
        unsafe { release_tree<K, V, A>(core.ptr.from_mut(self.a), root, true) }
    }
}

pub fn new_in<K, V, A: Allocator>(a: take A): SortedMap<K, V, A> {
    SortedMap(null_node<K, V>(), 0usize, a)
}
pub fn new<K, V>(): SortedMap<K, V> { new_in(Global()) }

fn null_node<K, V>(): ptr<mut Node<K, V>> { core.ptr.null_mut<Node<K, V>>() }

// Safety (all raw helpers): `n`/`p` are live nodes and indices are within the
// initialized range or, for slots being filled, within the node's capacity.
unsafe fn node_entry<K, V>(n: ptr<mut Node<K, V>>, i: usize): ptr<mut Bucket<K, V>> {
    (*n).entries.add(i)
}
unsafe fn node_child<K, V>(n: ptr<mut Node<K, V>>, i: usize): ptr<mut Node<K, V>> {
    *(*n).children.add(i)
}
// Stores link `i` of internal node `n` and records `n` as the child's parent.
unsafe fn set_child<K, V>(n: ptr<mut Node<K, V>>, i: usize, c: ptr<mut Node<K, V>>): Unit {
    *(*n).children.add(i) = c
    (*c).parent = n
}
unsafe fn copy_entries<K, V>(src: ptr<mut Bucket<K, V>>, dst: ptr<mut Bucket<K, V>>, count: usize): Unit {
    core.ptr.`copy`(src.cast_const(), dst, count)
}
unsafe fn copy_links<K, V>(src: ptr<mut ptr<mut Node<K, V>>>, dst: ptr<mut ptr<mut Node<K, V>>>, count: usize): Unit {
    core.ptr.`copy`(src.cast_const(), dst, count)
}
unsafe fn child_index<K, V>(p: ptr<mut Node<K, V>>, c: ptr<mut Node<K, V>>): usize {
    var i = 0usize
    while node_child(p, i) != c { i += 1usize }
    i
}
unsafe fn leftmost_leaf<K, V>(root: ptr<mut Node<K, V>>): ptr<mut Node<K, V>> {
    var n = root
    while !(*n).leaf { n = node_child(n, 0usize) }
    n
}
unsafe fn rightmost_leaf<K, V>(root: ptr<mut Node<K, V>>): ptr<mut Node<K, V>> {
    var n = root
    while !(*n).leaf { n = node_child(n, (*n).len) }
    n
}

// Position of the first / last entry in key order; a null node when empty.
unsafe fn first_pos<K, V>(root: ptr<mut Node<K, V>>): (ptr<mut Node<K, V>>, usize) {
    if root == null_node<K, V>() { return (null_node<K, V>(), 0usize) }
    (leftmost_leaf(root), 0usize)
}
unsafe fn last_pos<K, V>(root: ptr<mut Node<K, V>>): (ptr<mut Node<K, V>>, usize) {
    if root == null_node<K, V>() { return (null_node<K, V>(), 0usize) }
    let leaf = rightmost_leaf(root)
    (leaf, (*leaf).len - 1usize)
}
// Position after / before `(node, idx)`; a null node past either end.
unsafe fn successor<K, V>(node: ptr<mut Node<K, V>>, idx: usize): (ptr<mut Node<K, V>>, usize) {
    if !(*node).leaf { return (leftmost_leaf(node_child(node, idx + 1usize)), 0usize) }
    var n = node
    var i = idx + 1usize
    while i >= (*n).len {
        let p = (*n).parent
        if p == null_node<K, V>() { return (null_node<K, V>(), 0usize) }
        i = child_index(p, n)
        n = p
    }
    (n, i)
}
unsafe fn predecessor<K, V>(node: ptr<mut Node<K, V>>, idx: usize): (ptr<mut Node<K, V>>, usize) {
    if !(*node).leaf {
        let leaf = rightmost_leaf(node_child(node, idx))
        return (leaf, (*leaf).len - 1usize)
    }
    var n = node
    var i = idx
    while i == 0usize {
        let p = (*n).parent
        if p == null_node<K, V>() { return (null_node<K, V>(), 0usize) }
        i = child_index(p, n)
        n = p
    }
    (n, i - 1usize)
}

// Index of the first entry in `n` not below `key` and whether it equals `key`.
unsafe fn search_node<K, V, Q: Ord + unsized>(n: ptr<mut Node<K, V>>, key: read Q): (usize, bool) where K: KeyView<Q> {
    var lo = 0usize
    var hi = (*n).len
    while lo < hi {
        let mid = lo + (hi - lo) / 2usize
        let slot = node_entry(n, mid)
        let order = (*slot).key.key_view().cmp(key)
        if order.is_eq() { return (mid, true) }
        if order.is_lt() { lo = mid + 1usize } else { hi = mid }
    }
    (lo, false)
}
// Node and index of the entry whose key views as `key`.
unsafe fn find_slot<K, V, Q: Ord + unsized>(root: ptr<mut Node<K, V>>, key: read Q): (ptr<mut Node<K, V>>, usize)? where K: KeyView<Q> {
    if root == null_node<K, V>() { return none }
    var n = root
    while true {
        let found = search_node(n, key)
        if found.1 { return present((n, found.0)) }
        if (*n).leaf { return none }
        n = node_child(n, found.0)
    }
    none
}
// Position of the first entry whose key is not below `key`; null when none.
unsafe fn bound_pos<K, V, Q: Ord + unsized>(root: ptr<mut Node<K, V>>, key: read Q): (ptr<mut Node<K, V>>, usize) where K: KeyView<Q> {
    var best = (null_node<K, V>(), 0usize)
    var n = root
    while n != null_node<K, V>() {
        let found = search_node(n, key)
        if found.1 { return (n, found.0) }
        if found.0 < (*n).len { best = (n, found.0) }
        if (*n).leaf { break }
        n = node_child(n, found.0)
    }
    best
}

// Blocks come from the map's allocator through `a`, which outlives the call.
// Zero-sized element types need no block.
unsafe fn alloc_array<T, A: Allocator>(a: ptr<mut A>, count: usize): ptr<mut T> throws AllocError {
    let size = core.mem.size_of<T>()
    if size == 0usize { return dangling_for<T>() }
    let layout = layout_unchecked(size * count, core.mem.align_of<T>())
    let p = try (*a).allocate(layout)
    p.cast<T>()
}
unsafe fn free_array<T, A: Allocator>(a: ptr<mut A>, p: ptr<mut T>, count: usize): Unit {
    let size = core.mem.size_of<T>()
    if size == 0usize { return () }
    (*a).deallocate(p.cast<u8>(), layout_unchecked(size * count, core.mem.align_of<T>()))
}
// A fresh empty node; a failed step releases the blocks already taken.
unsafe fn alloc_node<K, V, A: Allocator>(a: ptr<mut A>, leaf: bool): ptr<mut Node<K, V>> throws AllocError {
    let entries = try alloc_array<Bucket<K, V>, A>(a, max_entries())
    let links = if leaf {
        core.ptr.null_mut<ptr<mut Node<K, V>>>()
    } else {
        match capture alloc_array<ptr<mut Node<K, V>>, A>(a, max_entries() + 1usize) {
            success(p) => p,
            failure(e) => {
                free_array<Bucket<K, V>, A>(a, entries, max_entries())
                throw e
            }
        }
    }
    let header = match capture alloc_array<Node<K, V>, A>(a, 1usize) {
        success(p) => p,
        failure(e) => {
            if !leaf { free_array<ptr<mut Node<K, V>>, A>(a, links, max_entries() + 1usize) }
            free_array<Bucket<K, V>, A>(a, entries, max_entries())
            throw e
        }
    }
    core.ptr.write(header, Node(entries, links, null_node<K, V>(), 0usize, leaf))
    header
}
// Releases the blocks of `n` only; its entries and children are not touched.
unsafe fn free_node<K, V, A: Allocator>(a: ptr<mut A>, n: ptr<mut Node<K, V>>): Unit {
    let leaf = (*n).leaf
    free_array<Bucket<K, V>, A>(a, (*n).entries, max_entries())
    if !leaf { free_array<ptr<mut Node<K, V>>, A>(a, (*n).children, max_entries() + 1usize) }
    free_array<Node<K, V>, A>(a, n, 1usize)
}
// Releases the subtree at `n` in key order, dropping its entries when
// `drop_entries` (a consuming iterator drops the unconsumed ones itself).
unsafe fn release_tree<K, V, A: Allocator>(a: ptr<mut A>, n: ptr<mut Node<K, V>>, drop_entries: bool): Unit {
    if n == null_node<K, V>() { return () }
    let len = (*n).len
    let leaf = (*n).leaf
    var i = 0usize
    while i < len {
        if !leaf { release_tree<K, V, A>(a, node_child(n, i), drop_entries) }
        if drop_entries { core.ptr.drop_in_place(node_entry(n, i)) }
        i += 1usize
    }
    if !leaf { release_tree<K, V, A>(a, node_child(n, len), drop_entries) }
    free_node<K, V, A>(a, n)
}

// Moves the upper half of the full child `i` of `p` into the empty node
// `right` (same height as the child) and lifts its median entry into `p` at
// `i`, with `right` as link `i + 1`. `p` is not full.
unsafe fn split_into<K, V>(p: ptr<mut Node<K, V>>, i: usize, right: ptr<mut Node<K, V>>): Unit {
    let left = node_child(p, i)
    let mid = min_entries()
    let upper = max_entries() - mid - 1usize
    copy_entries(node_entry(left, mid + 1usize), node_entry(right, 0usize), upper)
    if !(*left).leaf {
        var j = 0usize
        while j <= upper {
            set_child(right, j, node_child(left, mid + 1usize + j))
            j += 1usize
        }
    }
    (*right).len = upper
    (*left).len = mid
    let len = (*p).len
    copy_entries(node_entry(p, i), node_entry(p, i + 1usize), len - i)
    copy_links((*p).children.add(i + 1usize), (*p).children.add(i + 2usize), len - i)
    copy_entries(node_entry(left, mid), node_entry(p, i), 1usize)
    set_child(p, i + 1usize, right)
    (*p).len = len + 1usize
}

// Rebalancing steps; the child at `ci` of `p` has one entry fewer than allowed.
unsafe fn borrow_left<K, V>(p: ptr<mut Node<K, V>>, ci: usize): Unit {
    let n = node_child(p, ci)
    let left = node_child(p, ci - 1usize)
    let nlen = (*n).len
    let llen = (*left).len
    copy_entries(node_entry(n, 0usize), node_entry(n, 1usize), nlen)
    copy_entries(node_entry(p, ci - 1usize), node_entry(n, 0usize), 1usize)
    copy_entries(node_entry(left, llen - 1usize), node_entry(p, ci - 1usize), 1usize)
    if !(*n).leaf {
        copy_links((*n).children, (*n).children.add(1usize), nlen + 1usize)
        set_child(n, 0usize, node_child(left, llen))
    }
    (*left).len = llen - 1usize
    (*n).len = nlen + 1usize
}
unsafe fn borrow_right<K, V>(p: ptr<mut Node<K, V>>, ci: usize): Unit {
    let n = node_child(p, ci)
    let right = node_child(p, ci + 1usize)
    let nlen = (*n).len
    let rlen = (*right).len
    copy_entries(node_entry(p, ci), node_entry(n, nlen), 1usize)
    copy_entries(node_entry(right, 0usize), node_entry(p, ci), 1usize)
    copy_entries(node_entry(right, 1usize), node_entry(right, 0usize), rlen - 1usize)
    if !(*n).leaf {
        set_child(n, nlen + 1usize, node_child(right, 0usize))
        copy_links((*right).children.add(1usize), (*right).children, rlen)
    }
    (*right).len = rlen - 1usize
    (*n).len = nlen + 1usize
}

// Structural operations that free nodes go through the map's allocator.
extend<K, V, A: Allocator> SortedMap<K, V, A> {
    pub fn len(): usize { self.len }
    pub fn is_empty(): bool { self.len == 0usize }

    pub mut fn clear(): Unit {
        let root = self.root
        self.root = null_node<K, V>()
        self.len = 0usize
        unsafe { release_tree<K, V, A>(core.ptr.from_mut(self.a), root, true) }
    }

    // Merges the children `i` and `i + 1` of `p` and the entry between them
    // into child `i`, freeing child `i + 1`.
    mut unsafe fn merge_children(p: ptr<mut Node<K, V>>, i: usize): Unit {
        let l = node_child(p, i)
        let r = node_child(p, i + 1usize)
        let llen = (*l).len
        let rlen = (*r).len
        copy_entries(node_entry(p, i), node_entry(l, llen), 1usize)
        copy_entries(node_entry(r, 0usize), node_entry(l, llen + 1usize), rlen)
        if !(*l).leaf {
            var j = 0usize
            while j <= rlen {
                set_child(l, llen + 1usize + j, node_child(r, j))
                j += 1usize
            }
        }
        (*l).len = llen + 1usize + rlen
        let plen = (*p).len
        copy_entries(node_entry(p, i + 1usize), node_entry(p, i), plen - i - 1usize)
        copy_links((*p).children.add(i + 2usize), (*p).children.add(i + 1usize), plen - i - 1usize)
        (*p).len = plen - 1usize
        free_node<K, V, A>(core.ptr.from_mut(self.a), r)
    }

    // Restores the occupancy invariants after `start` lost an entry, walking
    // up while merges leave the parent short.
    mut unsafe fn rebalance(start: ptr<mut Node<K, V>>): Unit {
        var n = start
        while true {
            let parent = (*n).parent
            if parent == null_node<K, V>() {
                if (*n).len == 0usize {
                    if (*n).leaf {
                        self.root = null_node<K, V>()
                    } else {
                        let only = node_child(n, 0usize)
                        (*only).parent = null_node<K, V>()
                        self.root = only
                    }
                    free_node<K, V, A>(core.ptr.from_mut(self.a), n)
                }
                return ()
            }
            if (*n).len >= min_entries() { return () }
            let ci = child_index(parent, n)
            if ci > 0usize {
                if (*node_child(parent, ci - 1usize)).len > min_entries() {
                    borrow_left(parent, ci)
                    return ()
                }
            }
            if ci < (*parent).len {
                if (*node_child(parent, ci + 1usize)).len > min_entries() {
                    borrow_right(parent, ci)
                    return ()
                }
            }
            if ci > 0usize { self.merge_children(parent, ci - 1usize) } else { self.merge_children(parent, ci) }
            n = parent
        }
    }

    // Moves entry `i` of `node` out of the tree. An internal entry is replaced
    // by its in-order predecessor taken from a leaf.
    mut unsafe fn take_entry(node: ptr<mut Node<K, V>>, i: usize): Bucket<K, V> {
        let out = core.ptr.`read`(node_entry(node, i))
        var leaf = node
        if (*node).leaf {
            let len = (*node).len
            copy_entries(node_entry(node, i + 1usize), node_entry(node, i), len - i - 1usize)
            (*node).len = len - 1usize
        } else {
            leaf = rightmost_leaf(node_child(node, i))
            let last = (*leaf).len - 1usize
            copy_entries(node_entry(leaf, last), node_entry(node, i), 1usize)
            (*leaf).len = last
        }
        self.len -= 1usize
        self.rebalance(leaf)
        out
    }
}

extend<K: Ord, V, A: Allocator> SortedMap<K, V, A> {
    // Lookups take a borrowed query `Q` that the stored key views as (a
    // `String` key is searched with a `Text`); `Q`'s order must agree with `K`'s.
    pub fn contains_key<Q: Ord + unsized>(key: read Q): bool where K: KeyView<Q> {
        let hit = unsafe { find_slot(self.root, key) }
        match hit { present(_) => true, none => false }
    }
    pub fn get<Q: Ord + unsized>(key: read Q): (read V from self)? where K: KeyView<Q> {
        let hit = unsafe { find_slot(self.root, key) }
        match hit {
            present(at) => present(unsafe { read (*node_entry(at.0, at.1)).value }),
            none => none
        }
    }
    pub mut fn get_mut<Q: Ord + unsized>(key: read Q): (mut V from self)? where K: KeyView<Q> {
        let hit = unsafe { find_slot(self.root, key) }
        match hit {
            present(at) => present(unsafe { mut (*node_entry(at.0, at.1)).value }),
            none => none
        }
    }
    pub fn first_key(): (read K from self)? {
        if self.root == null_node<K, V>() { return none }
        let at = unsafe { first_pos(self.root) }
        present(unsafe { read (*node_entry(at.0, at.1)).key })
    }
    pub fn last_key(): (read K from self)? {
        if self.root == null_node<K, V>() { return none }
        let at = unsafe { last_pos(self.root) }
        present(unsafe { read (*node_entry(at.0, at.1)).key })
    }
    // Entries with `from <= key < to` in ascending key order; empty when
    // `to` is not above `from`.
    pub fn range(from: read K, to: read K): KeyRange<region self, K, V, A> {
        var start = (null_node<K, V>(), 0usize)
        var stop = (null_node<K, V>(), 0usize)
        if from.cmp(to).is_lt() {
            start = unsafe { bound_pos(self.root, from) }
            stop = unsafe { bound_pos(self.root, to) }
        }
        KeyRange(read self, start.0, start.1, stop.0, stop.1)
    }

    // Inserts or replaces; a replaced value is returned (the stored key is
    // kept and the new key dropped). Full nodes are split on the way down, so
    // on allocation failure the tree stays valid and the pair is dropped.
    mut fn try_insert_with_slot(key: take K, value: take V): (V?, mut V from self) throws AllocError {
        let a = core.ptr.from_mut(self.a)
        unsafe {
            if self.root == null_node<K, V>() {
                let leaf = try alloc_node<K, V, A>(a, true)
                self.root = leaf
            } else if (*self.root).len == max_entries() {
                let old = self.root
                let right = try alloc_node<K, V, A>(a, (*old).leaf)
                let top = match capture alloc_node<K, V, A>(a, false) {
                    success(n) => n,
                    failure(e) => {
                        free_node<K, V, A>(a, right)
                        throw e
                    }
                }
                set_child(top, 0usize, old)
                split_into(top, 0usize, right)
                self.root = top
            }
            var node = self.root
            while true {
                let found = search_node(node, key)
                var pos = found.0
                if found.1 {
                    let slot = core.ptr.from_mut((*node_entry(node, pos)).value)
                    let old = core.ptr.replace(slot, value)
                    return (present(old), mut (*node_entry(node, pos)).value)
                }
                if (*node).leaf {
                    let len = (*node).len
                    copy_entries(node_entry(node, pos), node_entry(node, pos + 1usize), len - pos)
                    core.ptr.write(node_entry(node, pos), Bucket(key, value))
                    (*node).len = len + 1usize
                    self.len += 1usize
                    let stored = mut (*node_entry(node, pos)).value
                    return (none, stored)
                }
                var next = node_child(node, pos)
                if (*next).len == max_entries() {
                    let right = try alloc_node<K, V, A>(a, (*next).leaf)
                    split_into(node, pos, right)
                    let middle = node_entry(node, pos)
                    let order = key.cmp((*middle).key)
                    if order.is_eq() {
                        let slot = core.ptr.from_mut((*middle).value)
                        let old = core.ptr.replace(slot, value)
                        return (present(old), mut (*middle).value)
                    }
                    if order.is_gt() { pos += 1usize }
                    next = node_child(node, pos)
                }
                node = next
            }
            package.core.panic.unreachable()
        }
    }
    pub mut fn try_insert(key: take K, value: take V): V? throws AllocError {
        let inserted = try self.try_insert_with_slot(key, value)
        inserted.0
    }
    pub mut fn insert(key: take K, value: take V): V? {
        let outcome = capture self.try_insert(key, value)
        match take outcome {
            success(old) => old,
            failure(_) => handle_alloc_error(layout_of<Node<K, V>>())
        }
    }
    pub mut fn remove<Q: Ord + unsized>(key: read Q): V? where K: KeyView<Q> {
        let hit = unsafe { find_slot(self.root, key) }
        match hit {
            present(at) => {
                let removed = unsafe { self.take_entry(at.0, at.1) }
                present(removed.value)
            },
            none => none
        }
    }
}

// An entry owns its lookup key and exclusively borrows the map until consumed.
// Occupied node positions remain stable while that loan prevents map mutation.
pub type OccupiedEntry<region r, K, V, A: Allocator = Global> {
    map: mut SortedMap<K, V, A> from r
    key: K
    node: ptr<mut Node<K, V>>
    index: usize
}
pub type VacantEntry<region r, K, V, A: Allocator = Global> {
    map: mut SortedMap<K, V, A> from r
    key: K
}
pub enum Entry<region r, K, V, A: Allocator = Global> {
    Occupied(OccupiedEntry<region r, K, V, A>);
    Vacant(VacantEntry<region r, K, V, A>)
}

extend<K: Ord, V, A: Allocator> SortedMap<K, V, A> {
    pub mut fn entry(key: take K): Entry<region self, K, V, A> {
        match unsafe { find_slot(self.root, key) } {
            present(at) => Entry.Occupied(OccupiedEntry(mut self, key, at.0, at.1)),
            none => Entry.Vacant(VacantEntry(mut self, key))
        }
    }
}

extend<region r, K: Ord, V, A: Allocator> OccupiedEntry<region r, K, V, A> {
    pub fn key(): read K from self {
        unsafe { read (*node_entry(self.node, self.index)).key }
    }
    pub fn get(): read V from self {
        unsafe { read (*node_entry(self.node, self.index)).value }
    }
    pub mut fn get_mut(): mut V from self {
        unsafe { mut (*node_entry(self.node, self.index)).value }
    }
    pub mut fn insert(value: take V): V {
        let slot = unsafe {
            core.ptr.from_mut((*node_entry(self.node, self.index)).value)
        }
        unsafe { core.ptr.replace(slot, value) }
    }
    pub take fn into_mut(): mut V from r {
        unsafe { mut (*node_entry(self.node, self.index)).value }
    }
    pub take fn remove(): V {
        match take self.map.remove(read self.key) {
            present(value) => value,
            none => package.core.panic.unreachable()
        }
    }
}

extend<region r, K: Ord, V, A: Allocator> VacantEntry<region r, K, V, A> {
    pub fn key(): read K from self { read self.key }
    pub take fn insert(value: take V): mut V from r {
        let outcome = capture self.map.try_insert_with_slot(self.key, value)
        match take outcome {
            success(result) => result.1,
            failure(_) => handle_alloc_error(layout_of<Node<K, V>>())
        }
    }
}

extend<region r, K: Ord, V, A: Allocator> Entry<region r, K, V, A> {
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

extend<region r, K: Ord, V: Default, A: Allocator> Entry<region r, K, V, A> {
    pub take fn or_default(): mut V from r {
        self.or_insert_with(take fn(): V { V.(Default).default() })
    }
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
    pub fn range(from: read K, to: read K): KeyRange<region self, K, Unit, A> { self.map.range(from, to) }
}

// Borrowed in-order iteration over the entries. `front` and `back` are the
// next positions to yield from each end and `left` entries remain, so the two
// ends never cross.
pub type EntryIter<region r, K, V, A: Allocator> {
    map: read SortedMap<K, V, A> from r
    front_node: ptr<mut Node<K, V>>
    front_idx: usize
    back_node: ptr<mut Node<K, V>>
    back_idx: usize
    left: usize
}
extend<region r, K, V, A: Allocator> EntryIter<region r, K, V, A> implements Iterator {
    type Item = read Bucket<K, V> from r
    mut fn next(): (read Bucket<K, V> from r)? {
        if self.left == 0usize { return none }
        let at = unsafe { node_entry(self.front_node, self.front_idx) }
        self.left -= 1usize
        if self.left != 0usize {
            let after = unsafe { successor(self.front_node, self.front_idx) }
            self.front_node = after.0
            self.front_idx = after.1
        }
        present(unsafe { read *at })
    }
}
extend<region r, K, V, A: Allocator> EntryIter<region r, K, V, A> implements BidirectionalIterator {
    mut fn next_back(): (read Bucket<K, V> from r)? {
        if self.left == 0usize { return none }
        let at = unsafe { node_entry(self.back_node, self.back_idx) }
        self.left -= 1usize
        if self.left != 0usize {
            let before = unsafe { predecessor(self.back_node, self.back_idx) }
            self.back_node = before.0
            self.back_idx = before.1
        }
        present(unsafe { read *at })
    }
}

// Borrowed iteration over the entries with keys in a half-open range.
pub type KeyRange<region r, K, V, A: Allocator> {
    map: read SortedMap<K, V, A> from r
    node: ptr<mut Node<K, V>>
    idx: usize
    end_node: ptr<mut Node<K, V>>
    end_idx: usize
}
extend<region r, K, V, A: Allocator> KeyRange<region r, K, V, A> implements Iterator {
    type Item = read Bucket<K, V> from r
    mut fn next(): (read Bucket<K, V> from r)? {
        if self.node == self.end_node && self.idx == self.end_idx { return none }
        let at = unsafe { node_entry(self.node, self.idx) }
        let after = unsafe { successor(self.node, self.idx) }
        self.node = after.0
        self.idx = after.1
        present(unsafe { read *at })
    }
}

// Iteration is in ascending key order.
extend<K, V, A: Allocator> SortedMap<K, V, A> implements Iterable {
    type Item = Bucket<K, V>
    type Iter<region r> = EntryIter<region r, K, V, A>
    fn iter<region r>(receiver self: read Self from r): EntryIter<region r, K, V, A> {
        let first = unsafe { first_pos(self.root) }
        let last = unsafe { last_pos(self.root) }
        EntryIter(read self, first.0, first.1, last.0, last.1, self.len)
    }
}
extend<K, A: Allocator> SortedSet<K, A> implements Iterable {
    type Item = Bucket<K, Unit>
    type Iter<region r> = EntryIter<region r, K, Unit, A>
    fn iter<region r>(receiver self: read Self from r): EntryIter<region r, K, Unit, A> {
        let first = unsafe { first_pos(self.map.root) }
        let last = unsafe { last_pos(self.map.root) }
        EntryIter(read self.map, first.0, first.1, last.0, last.1, self.map.len)
    }
}

// Consuming iteration owns the tree: entries are moved out in key order and
// the unconsumed ones are dropped, then every node is freed, when the
// iterator is dropped (also after stopping early).
pub type MapIntoIter<K, V, A: Allocator> {
    root: ptr<mut Node<K, V>>
    a: A
    node: ptr<mut Node<K, V>>
    idx: usize
    left: usize
    drop {
        unsafe {
            while self.left != 0usize {
                let n = self.node
                let i = self.idx
                self.left -= 1usize
                if self.left != 0usize {
                    let after = successor(n, i)
                    self.node = after.0
                    self.idx = after.1
                }
                core.ptr.drop_in_place(node_entry(n, i))
            }
            release_tree<K, V, A>(core.ptr.from_mut(self.a), self.root, false)
        }
    }
}
extend<K, V, A: Allocator> SortedMap<K, V, A> implements OwnedIterable {
    type Item = Bucket<K, V>
    type IntoIter = MapIntoIter<K, V, A>
    fn into_iter(receiver self: take Self): MapIntoIter<K, V, A> {
        unsafe {
            let root = self.root
            let n = self.len
            let first = first_pos(root)
            let a = core.ptr.`read`(core.ptr.from_ref(self.a))
            core.mem.forget(take self)
            MapIntoIter(root, a, first.0, first.1, n)
        }
    }
}
extend<K, V, A: Allocator> MapIntoIter<K, V, A> implements Iterator {
    type Item = Bucket<K, V>
    mut fn next(): Bucket<K, V>? {
        if self.left == 0usize { return none }
        let n = self.node
        let i = self.idx
        self.left -= 1usize
        if self.left != 0usize {
            let after = unsafe { successor(n, i) }
            self.node = after.0
            self.idx = after.1
        }
        present(unsafe { core.ptr.`read`(node_entry(n, i)) })
    }
}
extend<K, V, A: Allocator> MapIntoIter<K, V, A> {
    pub fn len(): usize { self.left }
}

pub type SetIntoIter<K, A: Allocator> { inner: MapIntoIter<K, Unit, A> }
extend<K, A: Allocator> SetIntoIter<K, A> implements Iterator {
    type Item = K
    mut fn next(): K? {
        match take self.inner.next() {
            present(entry) => present(entry.key),
            none => none
        }
    }
}
extend<K, A: Allocator> SortedSet<K, A> implements OwnedIterable {
    type Item = K
    type IntoIter = SetIntoIter<K, A>
    fn into_iter(receiver self: take Self): SetIntoIter<K, A> {
        SetIntoIter(self.map.into_iter())
    }
}

// Mutable iteration visits the values only, in key order: mutable keys could break the ordering.
pub type ValuesMut<region r, K, V, A: Allocator> {
    map: mut SortedMap<K, V, A> from r
    node: ptr<mut Node<K, V>>
    idx: usize
    left: usize
}
extend<region r, K, V, A: Allocator> ValuesMut<region r, K, V, A> implements Iterator {
    type Item = mut V from r
    mut fn next(): (mut V from r)? {
        if self.left == 0usize { return none }
        let at = unsafe { node_entry(self.node, self.idx) }
        self.left -= 1usize
        if self.left != 0usize {
            let after = unsafe { successor(self.node, self.idx) }
            self.node = after.0
            self.idx = after.1
        }
        present(unsafe { mut (*at).value })
    }
}
// Borrowed iterators over the keys or the values only.
pub type Keys<region r, K, V, A: Allocator> { inner: EntryIter<region r, K, V, A> }
extend<region r, K, V, A: Allocator> Keys<region r, K, V, A> implements Iterator {
    type Item = read K from r
    mut fn next(): (read K from r)? {
        match self.inner.next() { present(e) => present(read e.key), none => none }
    }
}
pub type Values<region r, K, V, A: Allocator> { inner: EntryIter<region r, K, V, A> }
extend<region r, K, V, A: Allocator> Values<region r, K, V, A> implements Iterator {
    type Item = read V from r
    mut fn next(): (read V from r)? {
        match self.inner.next() { present(e) => present(read e.value), none => none }
    }
}
extend<K, V, A: Allocator> SortedMap<K, V, A> {
    pub fn keys(): Keys<region self, K, V, A> {
        let first = unsafe { first_pos(self.root) }
        let last = unsafe { last_pos(self.root) }
        Keys(EntryIter(read self, first.0, first.1, last.0, last.1, self.len))
    }
    pub fn values(): Values<region self, K, V, A> {
        let first = unsafe { first_pos(self.root) }
        let last = unsafe { last_pos(self.root) }
        Values(EntryIter(read self, first.0, first.1, last.0, last.1, self.len))
    }
}
extend<K, V, A: Allocator> SortedMap<K, V, A> implements MutableIterable {
    type Item = V
    type IterMut<region r> = ValuesMut<region r, K, V, A>
    fn iter_mut<region r>(receiver self: mut Self from r): ValuesMut<region r, K, V, A> {
        let first = unsafe { first_pos(self.root) }
        let n = self.len
        ValuesMut(mut self, first.0, first.1, n)
    }
}
extend<K, V, A: Allocator> SortedMap<K, V, A> {
    pub mut fn values_mut(): ValuesMut<region self, K, V, A> {
        let first = unsafe { first_pos(self.root) }
        let n = self.len
        ValuesMut(mut self, first.0, first.1, n)
    }
}

// Copies the subtree at `n` node for node, giving the copy `parent`.
// A panicking `clone` leaks the partial copy.
unsafe fn clone_tree<K: Clone, V: Clone, A: Allocator>(a: ptr<mut A>, n: ptr<mut Node<K, V>>, parent: ptr<mut Node<K, V>>): ptr<mut Node<K, V>> {
    let twin = match capture alloc_node<K, V, A>(a, (*n).leaf) {
        success(c) => c,
        failure(_) => handle_alloc_error(layout_of<Node<K, V>>())
    }
    (*twin).parent = parent
    let len = (*n).len
    var i = 0usize
    while i < len {
        let e = node_entry(n, i)
        core.ptr.write(node_entry(twin, i), Bucket((*e).key.clone(), (*e).value.clone()))
        i += 1usize
    }
    if !(*n).leaf {
        var j = 0usize
        while j <= len {
            *(*twin).children.add(j) = clone_tree<K, V, A>(a, node_child(n, j), twin)
            j += 1usize
        }
    }
    (*twin).len = len
    twin
}
extend<K: Clone, V: Clone, A: Allocator + Clone> SortedMap<K, V, A> implements Clone {
    fn clone(): SortedMap<K, V, A> {
        var out = SortedMap(null_node<K, V>(), 0usize, self.a.clone())
        if self.root != null_node<K, V>() {
            let twin = unsafe { clone_tree<K, V, A>(core.ptr.from_mut(out.a), self.root, null_node<K, V>()) }
            out.root = twin
            out.len = self.len
        }
        out
    }
}
extend<K: PartialEq, V: PartialEq, A: Allocator> SortedMap<K, V, A> implements PartialEq {
    fn eq(other: read SortedMap<K, V, A>): bool {
        if self.len != other.len { return false }
        var x = unsafe { first_pos(self.root) }
        var y = unsafe { first_pos(other.root) }
        var left = self.len
        while left != 0usize {
            let a = unsafe { node_entry(x.0, x.1) }
            let b = unsafe { node_entry(y.0, y.1) }
            let ak = unsafe { read (*a).key }
            let bk = unsafe { read (*b).key }
            let av = unsafe { read (*a).value }
            let bv = unsafe { read (*b).value }
            if !ak.eq(bk) || !av.eq(bv) { return false }
            left -= 1usize
            if left != 0usize {
                x = unsafe { successor(x.0, x.1) }
                y = unsafe { successor(y.0, y.1) }
            }
        }
        true
    }
}
extend<K: Eq, V: Eq, A: Allocator> SortedMap<K, V, A> implements Eq {}
// Lexicographic over `(key, value)` entries in key order.
extend<K: PartialOrd, V: PartialOrd, A: Allocator> SortedMap<K, V, A> implements PartialOrd {
    fn partial_cmp(other: read SortedMap<K, V, A>): Ordering? {
        var x = unsafe { first_pos(self.root) }
        var y = unsafe { first_pos(other.root) }
        var left = self.len
        var right = other.len
        while left != 0usize && right != 0usize {
            let a = unsafe { node_entry(x.0, x.1) }
            let b = unsafe { node_entry(y.0, y.1) }
            let ak = unsafe { read (*a).key }
            let bk = unsafe { read (*b).key }
            let av = unsafe { read (*a).value }
            let bv = unsafe { read (*b).value }
            match ak.partial_cmp(bk) {
                present(o) => { if !o.is_eq() { return present(o) } },
                none => { return none }
            }
            match av.partial_cmp(bv) {
                present(o) => { if !o.is_eq() { return present(o) } },
                none => { return none }
            }
            left -= 1usize
            right -= 1usize
            if left != 0usize && right != 0usize {
                x = unsafe { successor(x.0, x.1) }
                y = unsafe { successor(y.0, y.1) }
            }
        }
        self.len.partial_cmp(other.len)
    }
}
extend<K: Ord, V: Ord, A: Allocator> SortedMap<K, V, A> implements Ord {
    fn cmp(other: read SortedMap<K, V, A>): Ordering {
        var x = unsafe { first_pos(self.root) }
        var y = unsafe { first_pos(other.root) }
        var left = self.len
        var right = other.len
        while left != 0usize && right != 0usize {
            let a = unsafe { node_entry(x.0, x.1) }
            let b = unsafe { node_entry(y.0, y.1) }
            let ak = unsafe { read (*a).key }
            let bk = unsafe { read (*b).key }
            let av = unsafe { read (*a).value }
            let bv = unsafe { read (*b).value }
            let k = ak.cmp(bk)
            if !k.is_eq() { return k }
            let v = av.cmp(bv)
            if !v.is_eq() { return v }
            left -= 1usize
            right -= 1usize
            if left != 0usize && right != 0usize {
                x = unsafe { successor(x.0, x.1) }
                y = unsafe { successor(y.0, y.1) }
            }
        }
        self.len.cmp(other.len)
    }
}
extend<K: Hash, V: Hash, A: Allocator> SortedMap<K, V, A> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit {
        state.write_usize(self.len)
        var x = unsafe { first_pos(self.root) }
        var left = self.len
        while left != 0usize {
            let a = unsafe { node_entry(x.0, x.1) }
            let ak = unsafe { read (*a).key }
            let av = unsafe { read (*a).value }
            ak.hash(mut state)
            av.hash(mut state)
            left -= 1usize
            if left != 0usize { x = unsafe { successor(x.0, x.1) } }
        }
    }
}
extend<K: fmt.Debug, V: fmt.Debug, A: Allocator> SortedMap<K, V, A> implements fmt.Debug {
    fn fmt<W: fmt.Write>(f: mut fmt.Formatter<W>): Unit throws fmt.Error {
        try f.debug_open("{")
        var x = unsafe { first_pos(self.root) }
        var left = self.len
        var first = true
        while left != 0usize {
            let a = unsafe { node_entry(x.0, x.1) }
            let ak = unsafe { read (*a).key }
            let av = unsafe { read (*a).value }
            try f.debug_item_start(first)
            try K.(fmt.Debug).fmt(ak, mut f)
            try f.write_str(": ")
            try V.(fmt.Debug).fmt(av, mut f)
            try f.debug_item_end()
            first = false
            left -= 1usize
            if left != 0usize { x = unsafe { successor(x.0, x.1) } }
        }
        try f.debug_close("}", self.len == 0usize)
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
        var x = unsafe { first_pos(self.map.root) }
        var left = self.map.len
        var first = true
        while left != 0usize {
            let a = unsafe { node_entry(x.0, x.1) }
            let ak = unsafe { read (*a).key }
            try f.debug_item_start(first)
            try K.(fmt.Debug).fmt(ak, mut f)
            try f.debug_item_end()
            first = false
            left -= 1usize
            if left != 0usize { x = unsafe { successor(x.0, x.1) } }
        }
        try f.debug_close("}", self.map.len == 0usize)
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
