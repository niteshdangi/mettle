import core.iter.{Iterator, BidirectionalIterator, ExactSizeIterator, FusedIterator, Bound, RangeBounds, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems}
import core.clone.Clone
import core.default.Default
import core.cmp.{Eq, PartialEq, PartialOrd}
import core.hash.{Hash, Hasher}
import core.fmt
import super.alloc.{Allocator, Global, AllocError, layout_unchecked, layout_of, handle_alloc_error, dangling_for, free_block}
import core.cmp.{Ord, Ordering}
import core.borrow.KeyView

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
    subtree_len: usize
    leaf: bool
}

fn max_entries(): usize { 11usize }
fn min_entries(): usize { 5usize }

pub type SortedMap<K, V, A: Allocator = Global> {
    root: ptr<mut Node<K, V>>
    len: usize
    a: A
    drop {
        let root = self.root
        let len = self.len
        self.root = null_node<K, V>()
        self.len = 0usize
        unsafe { drop_tree<K, V, A>(core.ptr.from_mut(self.a), root, len) }
    }
}

pub fn new_in<K, V, A: Allocator>(take a: A): SortedMap<K, V, A> {
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
unsafe fn position_at_rank<K, V>(root: ptr<mut Node<K, V>>, rank: usize): (ptr<mut Node<K, V>>, usize) {
    var at = first_pos(root)
    var i = 0usize
    while i < rank {
        at = successor(at.0, at.1)
        i += 1usize
    }
    at
}

// Index of the first entry in `n` not below `key` and whether it equals `key`.
unsafe fn search_node<K, V, Q: Ord + unsized>(n: ptr<mut Node<K, V>>, read key: Q): (usize, bool) where K: KeyView<Q> {
    var lo = 0usize
    var hi = (*n).len
    while lo < hi {
        let mid = lo + (hi - lo) / 2usize
        let slot = node_entry(n, mid)
        let order = Q.(Ord).cmp(K.(KeyView<Q>).key_view((*slot).key), key)
        if order.is_eq() { return (mid, true) }
        if order.is_lt() { lo = mid + 1usize } else { hi = mid }
    }
    (lo, false)
}
// Node and index of the entry whose key views as `key`.
unsafe fn find_slot<K, V, Q: Ord + unsized>(root: ptr<mut Node<K, V>>, read key: Q): (ptr<mut Node<K, V>>, usize)? where K: KeyView<Q> {
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
unsafe fn bound_pos<K, V, Q: Ord + unsized>(root: ptr<mut Node<K, V>>, read key: Q): (ptr<mut Node<K, V>>, usize) where K: KeyView<Q> {
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
// Position of the first entry strictly greater than `key`; null when none.
unsafe fn upper_bound_pos<K, V, Q: Ord + unsized>(root: ptr<mut Node<K, V>>, read key: Q): (ptr<mut Node<K, V>>, usize) where K: KeyView<Q> {
    var best = (null_node<K, V>(), 0usize)
    var n = root
    while n != null_node<K, V>() {
        let found = search_node(n, key)
        let i = if found.1 { found.0 + 1usize } else { found.0 }
        if i < (*n).len { best = (n, i) }
        if (*n).leaf { break }
        n = node_child(n, i)
    }
    best
}

fn range_positions<region r, K, V, Q: Ord + unsized>(
    root: ptr<mut Node<K, V>>,
    take start: Bound<read Q from r>,
    take end: Bound<read Q from r>
): ((ptr<mut Node<K, V>>, usize), (ptr<mut Node<K, V>>, usize)) where K: KeyView<Q> {
    let invalid = match read start {
        Bound.Included(low) => match read end {
            Bound.Included(high) => Q.(Ord).cmp(low, high).is_gt(),
            Bound.Excluded(high) => Q.(Ord).cmp(low, high).is_gt(),
            Bound.Unbounded => false
        },
        Bound.Excluded(low) => match read end {
            Bound.Included(high) => Q.(Ord).cmp(low, high).is_gt(),
            Bound.Excluded(high) => {
                let order = Q.(Ord).cmp(low, high)
                order.is_gt() || order.is_eq()
            },
            Bound.Unbounded => false
        },
        Bound.Unbounded => false
    }
    if invalid { super.alloc.panic_precondition() }
    let start_pos = match take start {
        Bound.Included(key) => unsafe { bound_pos(root, key) },
        Bound.Excluded(key) => unsafe { upper_bound_pos(root, key) },
        Bound.Unbounded => unsafe { first_pos(root) }
    }
    let end_pos = match take end {
        Bound.Included(key) => unsafe { upper_bound_pos(root, key) },
        Bound.Excluded(key) => unsafe { bound_pos(root, key) },
        Bound.Unbounded => (null_node<K, V>(), 0usize)
    }
    (start_pos, end_pos)
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
    let entries_free = free_block(
        entries.cast<u8>(),
        layout_unchecked(core.mem.size_of<Bucket<K, V>>() * max_entries(), core.mem.align_of<Bucket<K, V>>()),
        a
    )
    let links = if leaf {
        core.ptr.null_mut<ptr<mut Node<K, V>>>()
    } else {
        try alloc_array<ptr<mut Node<K, V>>, A>(a, max_entries() + 1usize)
    }
    let links_free = if leaf { none } else {
        present(free_block(
            links.cast<u8>(),
            layout_unchecked(
                core.mem.size_of<ptr<mut Node<K, V>>>() * (max_entries() + 1usize),
                core.mem.align_of<ptr<mut Node<K, V>>>()
            ),
            a
        ))
    }
    let header = try alloc_array<Node<K, V>, A>(a, 1usize)
    core.ptr.write(header, Node(entries, links, null_node<K, V>(), 0usize, 0usize, leaf))
    core.mem.forget(take links_free)
    core.mem.forget(take entries_free)
    header
}
// Releases the blocks of `n` only; its entries and children are not touched.
unsafe fn free_node<K, V, A: Allocator>(a: ptr<mut A>, n: ptr<mut Node<K, V>>): Unit {
    let header = core.ptr.`read`(n.cast_const())
    let header_free = free_block(n.cast<u8>(), layout_of<Node<K, V>>(), a)
    let links_free = if header.leaf { none } else {
        present(free_block(
            header.children.cast<u8>(),
            layout_unchecked(
                core.mem.size_of<ptr<mut Node<K, V>>>() * (max_entries() + 1usize),
                core.mem.align_of<ptr<mut Node<K, V>>>()
            ),
            a
        ))
    }
    let entries_free = free_block(
        header.entries.cast<u8>(),
        layout_unchecked(
            core.mem.size_of<Bucket<K, V>>() * max_entries(),
            core.mem.align_of<Bucket<K, V>>()
        ),
        a
    )
}

unsafe fn recount_node<K, V>(node: ptr<mut Node<K, V>>): Unit {
    let len = (*node).len
    var total = len
    if !(*node).leaf {
        var index = 0usize
        while index <= len {
            total += (*node_child(node, index)).subtree_len
            index += 1usize
        }
    }
    (*node).subtree_len = total
}

unsafe fn recount_path<K, V>(start: ptr<mut Node<K, V>>): Unit {
    var node = start
    while node != null_node<K, V>() {
        recount_node(node)
        node = (*node).parent
    }
}

unsafe fn tree_node_counts<K, V>(node: ptr<mut Node<K, V>>): (usize, usize) {
    if (*node).leaf { return (1usize, 0usize) }
    var leaves = 0usize
    var branches = 1usize
    var index = 0usize
    while index <= (*node).len {
        let counts = tree_node_counts(node_child(node, index))
        leaves += counts.0
        branches += counts.1
        index += 1usize
    }
    (leaves, branches)
}

fn bulk_capacity(height: usize): usize {
    var capacity = max_entries()
    var level = 0usize
    while level < height {
        capacity = capacity.saturating_mul(max_entries() + 1usize).saturating_add(max_entries())
        level += 1usize
    }
    capacity
}

fn bulk_node_counts(len: usize, height: usize): (usize, usize) {
    if height == 0usize { return (1usize, 0usize) }
    let children = len / (bulk_capacity(height - 1usize) + 1usize) + 1usize
    let entries = len - children + 1usize
    let base = entries / children
    let extra = entries % children
    let low = bulk_node_counts(base, height - 1usize)
    if extra == 0usize { return (low.0 * children, low.1 * children + 1usize) }
    let high = bulk_node_counts(base + 1usize, height - 1usize)
    (low.0 * (children - extra) + high.0 * extra,
     low.1 * (children - extra) + high.1 * extra + 1usize)
}

type BulkNodes<K, V, A: Allocator> {
    a: ptr<mut A>
    leaves: ptr<mut Node<K, V>>
    branches: ptr<mut Node<K, V>>
    pending: ptr<mut Node<K, V>>
    drop { self.run() }
}

extend<K, V, A: Allocator> BulkNodes<K, V, A> {
    mut unsafe fn add(node: ptr<mut Node<K, V>>): Unit {
        (*node).len = 0usize
        (*node).subtree_len = 0usize
        if (*node).leaf {
            (*node).parent = self.leaves
            self.leaves = node
        } else {
            (*node).parent = self.branches
            self.branches = node
        }
    }

    mut unsafe fn collect(node: ptr<mut Node<K, V>>): Unit {
        if !(*node).leaf {
            var index = 0usize
            while index <= (*node).len {
                self.collect(node_child(node, index))
                index += 1usize
            }
        }
        self.add(node)
    }

    mut unsafe fn take_node(leaf: bool): ptr<mut Node<K, V>> {
        let node = if leaf { self.leaves } else { self.branches }
        if leaf { self.leaves = (*node).parent } else { self.branches = (*node).parent }
        (*node).parent = null_node<K, V>()
        node
    }

    mut unsafe fn build(len: usize, height: usize, mut entries: super.vec.List<Bucket<K, V>>): ptr<mut Node<K, V>> {
        let node = self.take_node(height == 0usize)
        if height == 0usize {
            let start = entries.len() - len
            copy_entries(entries.as_mut_ptr().add(start), node_entry(node, 0usize), len)
            entries.set_len(start)
            (*node).len = len
            (*node).subtree_len = len
            return node
        }
        let children = len / (bulk_capacity(height - 1usize) + 1usize) + 1usize
        let remaining = len - children + 1usize
        let base = remaining / children
        let extra = remaining % children
        var index = children
        while index != 0usize {
            index -= 1usize
            let child = self.build(base + (if index < extra { 1usize } else { 0usize }), height - 1usize, mut entries)
            set_child(node, index, child)
            if index != 0usize {
                core.ptr.write(node_entry(node, index - 1usize), entries.pop().or_panic())
            }
        }
        (*node).len = children - 1usize
        (*node).subtree_len = len
        node
    }

    mut fn run(): Unit {
        unsafe {
            while true {
                if self.pending == null_node<K, V>() {
                    if self.leaves != null_node<K, V>() {
                        self.pending = self.take_node(true)
                    } else if self.branches != null_node<K, V>() {
                        self.pending = self.take_node(false)
                    } else { break }
                }
                let node = self.pending
                let entries = (*node).entries
                (*node).entries = core.ptr.null_mut<Bucket<K, V>>()
                if entries != core.ptr.null_mut<Bucket<K, V>>() {
                    free_array<Bucket<K, V>, A>(self.a, entries, max_entries())
                }
                let children = (*node).children
                (*node).children = core.ptr.null_mut<ptr<mut Node<K, V>>>()
                if children != core.ptr.null_mut<ptr<mut Node<K, V>>>() {
                    free_array<ptr<mut Node<K, V>>, A>(self.a, children, max_entries() + 1usize)
                }
                self.pending = null_node<K, V>()
                free_array<Node<K, V>, A>(self.a, node, 1usize)
            }
        }
    }
}

type DetachedNodes<K, V, A: Allocator> {
    a: ptr<mut A>
    nodes: super.vec.List<ptr<mut Node<K, V>>>
    drop { self.run() }
}

extend<K, V, A: Allocator> DetachedNodes<K, V, A> {
    mut fn run(): Unit {
        while true {
            match self.nodes.pop() {
                present(node) => unsafe { free_node<K, V, A>(self.a, node) },
                none => { break }
            }
        }
    }
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

// Safety: the cursor skips dropped entries; all node headers and child links stay live.
type TreeDrop<K, V, A: Allocator> {
    a: ptr<mut A>
    root: ptr<mut Node<K, V>>
    node: ptr<mut Node<K, V>>
    index: usize
    remaining: usize
    drop { self.run() }
}

extend<K, V, A: Allocator> TreeDrop<K, V, A> {
    mut fn run(): Unit {
        unsafe {
            while self.remaining != 0usize {
                let node = self.node
                let index = self.index
                self.remaining -= 1usize
                if self.remaining != 0usize {
                    let next = successor(node, index)
                    self.node = next.0
                    self.index = next.1
                }
                core.ptr.drop_in_place(node_entry(node, index))
            }
            let root = self.root
            self.root = null_node<K, V>()
            release_tree<K, V, A>(self.a, root, false)
        }
    }
}

// Safety: root owns len initialized entries; links stay live until the guard finishes.
unsafe fn drop_tree<K, V, A: Allocator>(a: ptr<mut A>, root: ptr<mut Node<K, V>>, len: usize): Unit {
    let first = first_pos(root)
    var remaining = TreeDrop(a, root, first.0, first.1, len)
    remaining.run()
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
    recount_node(left)
    recount_node(right)
    recount_node(p)
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
    recount_node(left)
    recount_node(n)
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
    recount_node(right)
    recount_node(n)
}

// Structural operations that free nodes go through the map's allocator.
extend<K, V, A: Allocator> SortedMap<K, V, A> {
    pub fn len(): usize { self.len }
    pub fn is_empty(): bool { self.len == 0usize }

    pub mut fn clear(): Unit {
        let root = self.root
        let len = self.len
        self.root = null_node<K, V>()
        self.len = 0usize
        unsafe { drop_tree<K, V, A>(core.ptr.from_mut(self.a), root, len) }
    }

    mut unsafe fn merge_children(p: ptr<mut Node<K, V>>, i: usize): ptr<mut Node<K, V>> {
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
        (*l).subtree_len += (*r).subtree_len + 1usize
        let plen = (*p).len
        copy_entries(node_entry(p, i + 1usize), node_entry(p, i), plen - i - 1usize)
        copy_links((*p).children.add(i + 2usize), (*p).children.add(i + 1usize), plen - i - 1usize)
        (*p).len = plen - 1usize
        r
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
            let detached = if ci > 0usize {
                self.merge_children(parent, ci - 1usize)
            } else { self.merge_children(parent, ci) }
            free_node<K, V, A>(core.ptr.from_mut(self.a), detached)
            n = parent
        }
    }

    mut unsafe fn repair_split_border(
        right: bool, mut detached: super.vec.List<ptr<mut Node<K, V>>>
    ): Unit {
        var node = self.root
        while !(*node).leaf {
            let at = if right { (*node).len } else { 0usize }
            if (*node_child(node, at)).len <= min_entries() && (*node).len != 0usize {
                let sibling = if right { at - 1usize } else { at + 1usize }
                if (*node_child(node, at)).len + (*node_child(node, sibling)).len + 1usize <= max_entries() {
                    detached.push(self.merge_children(node, if right { at - 1usize } else { at }))
                } else {
                    while (*node_child(node, at)).len <= min_entries() {
                        if right { borrow_left(node, at) } else { borrow_right(node, at) }
                    }
                }
            }
            let child = node_child(node, if right { (*node).len } else { 0usize })
            if node == self.root && (*node).len == 0usize {
                self.root = child
                (*child).parent = null_node<K, V>()
                detached.push(take node)
            }
            node = child
        }
        if node == self.root && (*node).len == 0usize {
            self.root = null_node<K, V>()
            detached.push(take node)
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
        var ancestor = leaf
        while ancestor != null_node<K, V>() {
            (*ancestor).subtree_len -= 1usize
            ancestor = (*ancestor).parent
        }
        self.rebalance(leaf)
        out
    }
}

extend<K: Ord, V, A: Allocator> SortedMap<K, V, A> {
    // Lookups take a borrowed query `Q` that the stored key views as (a
    // `String` key is searched with a `Text`); `Q`'s order must agree with `K`'s.
    pub fn contains_key<Q: Ord + unsized>(read key: Q): bool where K: KeyView<Q> {
        let hit = unsafe { find_slot(self.root, key) }
        match hit { present(_) => true, none => false }
    }
    pub fn get<Q: Ord + unsized>(read key: Q): (read V from self)? where K: KeyView<Q> {
        let hit = unsafe { find_slot(self.root, key) }
        match hit {
            present(at) => present(unsafe { read (*node_entry(at.0, at.1)).value }),
            none => none
        }
    }
    pub fn get_key_value<Q: Ord + unsized>(read key: Q): (read K from self, read V from self)? where K: KeyView<Q> {
        let hit = unsafe { find_slot(self.root, key) }
        match hit {
            present(at) => {
                let entry = unsafe { node_entry(at.0, at.1) }
                unsafe { present((read (*entry).key, read (*entry).value)) }
            },
            none => none
        }
    }
    pub mut fn get_mut<Q: Ord + unsized>(read key: Q): (mut V from self)? where K: KeyView<Q> {
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
    pub fn first_key_value(): (read K from self, read V from self)? {
        if self.root == null_node<K, V>() { return none }
        let at = unsafe { first_pos(self.root) }
        let entry = unsafe { node_entry(at.0, at.1) }
        unsafe { present((read (*entry).key, read (*entry).value)) }
    }
    pub fn last_key_value(): (read K from self, read V from self)? {
        if self.root == null_node<K, V>() { return none }
        let at = unsafe { last_pos(self.root) }
        let entry = unsafe { node_entry(at.0, at.1) }
        unsafe { present((read (*entry).key, read (*entry).value)) }
    }
    pub mut fn first_entry(): OccupiedEntry<region self, K, V, A>? {
        if self.root == null_node<K, V>() { return none }
        let at = unsafe { first_pos(self.root) }
        present(OccupiedEntry(mut self, at.0, at.1))
    }
    pub mut fn last_entry(): OccupiedEntry<region self, K, V, A>? {
        if self.root == null_node<K, V>() { return none }
        let at = unsafe { last_pos(self.root) }
        present(OccupiedEntry(mut self, at.0, at.1))
    }
    pub mut fn pop_first(): (K, V)? {
        if self.root == null_node<K, V>() { return none }
        let at = unsafe { first_pos(self.root) }
        let entry = unsafe { self.take_entry(at.0, at.1) }
        present((entry.key, entry.value))
    }
    pub mut fn pop_last(): (K, V)? {
        if self.root == null_node<K, V>() { return none }
        let at = unsafe { last_pos(self.root) }
        let entry = unsafe { self.take_entry(at.0, at.1) }
        present((entry.key, entry.value))
    }
    pub fn range<Q: Ord + unsized, R: RangeBounds<Q>>(
        take bounds: R
    ): KeyRange<region self, K, V, A> where K: KeyView<Q> {
        let positions = range_positions(
            self.root,
            R.(RangeBounds<Q>).start_bound(read bounds),
            R.(RangeBounds<Q>).end_bound(read bounds)
        )
        KeyRange(read self, positions.0.0, positions.0.1, positions.1.0, positions.1.1)
    }
    pub mut fn range_mut<Q: Ord + unsized, R: RangeBounds<Q>>(
        take bounds: R
    ): RangeMut<region self, K, V, A> where K: KeyView<Q> {
        let positions = range_positions(
            self.root,
            R.(RangeBounds<Q>).start_bound(read bounds),
            R.(RangeBounds<Q>).end_bound(read bounds)
        )
        let empty = positions.0.0 == positions.1.0 && positions.0.1 == positions.1.1
        let back = if empty {
            positions.1
        } else if positions.1.0 == null_node<K, V>() {
            unsafe { last_pos(self.root) }
        } else {
            unsafe { predecessor(positions.1.0, positions.1.1) }
        }
        RangeMut(present(mut self), positions.0.0, positions.0.1, back.0, back.1, empty)
    }
    pub mut fn extract_if<R: RangeBounds<K>, F: mut fn(read K, mut V): bool>(
        take bounds: R, take predicate: F
    ): MapExtractIf<region self, K, V, A, R, F> where K: KeyView<K> {
        let positions = range_positions(
            self.root,
            R.(RangeBounds<K>).start_bound(read bounds),
            R.(RangeBounds<K>).end_bound(read bounds)
        )
        MapExtractIf(mut self, predicate, bounds, positions.0.0, positions.0.1, positions.1.0, positions.1.1)
    }
    pub mut fn retain<F: mut fn(read K, mut V): bool>(take predicate: F): Unit {
        var keep = predicate
        var at = unsafe { first_pos(self.root) }
        while at.0 != null_node<K, V>() {
            let entry = unsafe { node_entry(at.0, at.1) }
            if keep(unsafe { read (*entry).key }, unsafe { mut (*entry).value }) {
                at = unsafe { successor(at.0, at.1) }
            } else {
                at = {
                    let removed = unsafe { self.take_entry(at.0, at.1) }
                    unsafe { bound_pos(self.root, read removed.key) }
                }
            }
        }
    }
    pub mut fn split_off(read key: K): SortedMap<K, V, A> where A: Clone {
        var upper = new_in<K, V, A>(self.a.clone())
        if self.len == 0usize { return upper }
        if upper.a.is_compatible(read self.a) {
            if !self.first_key().or_panic().cmp(key).is_lt() {
                upper.root = self.root
                upper.len = self.len
                self.root = null_node<K, V>()
                self.len = 0usize
                return upper
            }
            if self.last_key().or_panic().cmp(key).is_lt() { return upper }
            var positions = super.vec.new<usize>()
            var node = self.root
            unsafe {
                while true {
                    let found = search_node(node, key)
                    let leaf = (*node).leaf
                    if !leaf { node = node_child(node, found.0) }
                    positions.push(take found.0)
                    if leaf { break }
                }
            }
            var detached = DetachedNodes(
                core.ptr.from_mut(self.a),
                super.vec.with_capacity<ptr<mut Node<K, V>>>(positions.len() * 4usize)
            )
            var level = 0usize
            while level < positions.len() {
                let fresh = match capture unsafe {
                    alloc_node<K, V, A>(core.ptr.from_mut(upper.a), level == 0usize)
                } {
                    success(fresh) => fresh,
                    failure(_) => handle_alloc_error(layout_of<Node<K, V>>())
                }
                if level != 0usize { unsafe { set_child(fresh, 0usize, upper.root) } }
                upper.root = fresh
                level += 1usize
            }
            unsafe {
                var left = self.root
                var right = upper.root
                level = 0usize
                while true {
                    let at = positions[level]
                    let count = (*left).len - at
                    copy_entries(node_entry(left, at), node_entry(right, 0usize), count)
                    (*left).len = at
                    (*right).len = count
                    if (*left).leaf { break }
                    var index = 1usize
                    while index <= count {
                        set_child(right, index, node_child(left, at + index))
                        index += 1usize
                    }
                    left = node_child(left, at)
                    right = node_child(right, 0usize)
                    level += 1usize
                }
                recount_path(left)
                recount_path(right)
                upper.len = (*upper.root).subtree_len
                self.len = (*self.root).subtree_len
                self.repair_split_border(true, mut detached.nodes)
                upper.repair_split_border(false, mut detached.nodes)
            }
            detached.run()
            return upper
        }
        while true {
            match self.last_key() {
                present(last) => { if K.(Ord).cmp(last, key).is_lt() { break } },
                none => { break }
            }
            match take self.pop_last() {
                present(entry) => { let _old = upper.insert(take entry.0, take entry.1) },
                none => { break }
            }
        }
        upper
    }

    // Inserts or replaces; a replaced value is returned (the stored key is
    // kept and the new key dropped). Full nodes are split on the way down, so
    // on allocation failure the tree stays valid and the pair is dropped.
    mut fn try_insert_with_slot(take key: K, take value: V): (V?, ptr<mut Node<K, V>>, usize) throws AllocError {
        let a = core.ptr.from_mut(self.a)
        unsafe {
            if self.root == null_node<K, V>() {
                let leaf = try alloc_node<K, V, A>(a, true)
                self.root = leaf
            } else if (*self.root).len == max_entries() {
                let old = self.root
                let right = try alloc_node<K, V, A>(a, (*old).leaf)
                var right_guard = CloneNodeGuard(a, right, 0usize, 0usize)
                let top = try alloc_node<K, V, A>(a, false)
                set_child(top, 0usize, old)
                split_into(top, 0usize, right)
                self.root = top
                right_guard.node = null_node<K, V>()
            }
            var node = self.root
            while true {
                let found = search_node(node, key)
                var pos = found.0
                if found.1 {
                    let slot = core.ptr.from_mut((*node_entry(node, pos)).value)
                    let old = core.ptr.replace(slot, value)
                    return (present(old), node, pos)
                }
                if (*node).leaf {
                    let len = (*node).len
                    copy_entries(node_entry(node, pos), node_entry(node, pos + 1usize), len - pos)
                    core.ptr.write(node_entry(node, pos), Bucket(key, value))
                    (*node).len = len + 1usize
                    self.len += 1usize
                    var ancestor = node
                    while ancestor != null_node<K, V>() {
                        (*ancestor).subtree_len += 1usize
                        ancestor = (*ancestor).parent
                    }
                    return (none, node, pos)
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
                        return (present(old), node, pos)
                    }
                    if order.is_gt() { pos += 1usize }
                    next = node_child(node, pos)
                }
                node = next
            }
            core.panic.unreachable()
        }
    }
    pub mut fn try_insert(take key: K, take value: V): V? throws AllocError {
        let inserted = try self.try_insert_with_slot(take key, take value)
        inserted.0
    }
    pub mut fn insert(take key: K, take value: V): V? {
        let outcome = capture self.try_insert(take key, take value)
        match take outcome {
            success(old) => old,
            failure(_) => handle_alloc_error(layout_of<Node<K, V>>())
        }
    }
    pub mut fn remove<Q: Ord + unsized>(read key: Q): V? where K: KeyView<Q> {
        match take self.remove_entry(key) {
            present(entry) => present(entry.1),
            none => none
        }
    }
    pub mut fn remove_entry<Q: Ord + unsized>(read key: Q): (K, V)? where K: KeyView<Q> {
        let hit = unsafe { find_slot(self.root, key) }
        match hit {
            present(at) => {
                let removed = unsafe { self.take_entry(at.0, at.1) }
                present((removed.key, removed.value))
            },
            none => none
        }
    }
}

extend<K: Ord, V, A: Allocator> SortedMap<K, V, A> {
    mut unsafe fn join_disjoint(mut other: SortedMap<K, V, A>, other_first: bool): Unit {
        let total = self.len + other.len
        let middle = if other_first {
            let at = last_pos(other.root)
            other.take_entry(at.0, at.1)
        } else {
            let at = first_pos(other.root)
            other.take_entry(at.0, at.1)
        }
        if other.len == 0usize {
            let _ = self.insert(take middle.key, take middle.value)
            return ()
        }
        var left = if other_first { other.root } else { self.root }
        var right = if other_first { self.root } else { other.root }
        var left_level = left
        var right_level = right
        while !(*left_level).leaf && !(*right_level).leaf {
            left_level = node_child(left_level, 0usize)
            right_level = node_child(right_level, 0usize)
        }
        let a = core.ptr.from_mut(self.a)
        var parent = null_node<K, V>()
        var pos = 0usize
        var root = null_node<K, V>()
        if (*left_level).leaf && (*right_level).leaf &&
            (*left).len + (*right).len + 1usize <= max_entries() {
            let llen = (*left).len
            let rlen = (*right).len
            core.ptr.write(node_entry(left, llen), middle)
            copy_entries(node_entry(right, 0usize), node_entry(left, llen + 1usize), rlen)
            if !(*left).leaf {
                var j = 0usize
                while j <= rlen {
                    set_child(left, llen + 1usize + j, node_child(right, j))
                    j += 1usize
                }
            }
            (*left).len = llen + 1usize + rlen
            (*left).subtree_len = total
            other.root = null_node<K, V>()
            other.len = 0usize
            self.root = left
            self.len = total
            free_node<K, V, A>(a, right)
            return ()
        }
        if (*left_level).leaf && (*right_level).leaf {
            parent = self.join_node(a, false)
            set_child(parent, 0usize, left)
            set_child(parent, 1usize, right)
            (*parent).len = 1usize
            root = parent
        } else {
            let append_right = !(*left_level).leaf
            var extra = if append_right { left_level } else { right_level }
            var levels = 0usize
            while !(*extra).leaf {
                extra = node_child(extra, 0usize)
                levels += 1usize
            }
            var tall = if append_right { left } else { right }
            if (*tall).len == max_entries() {
                let sibling = self.join_node(a, (*tall).leaf)
                var sibling_guard = CloneNodeGuard(a, sibling, 0usize, 0usize)
                let top = self.join_node(a, false)
                set_child(top, 0usize, tall)
                split_into(top, 0usize, sibling)
                sibling_guard.node = null_node<K, V>()
                tall = top
                levels += 1usize
                if append_right == other_first {
                    other.root = top
                } else {
                    self.root = top
                }
            }
            root = tall
            while levels > 0usize {
                var at = if append_right { (*tall).len } else { 0usize }
                var child = node_child(tall, at)
                if levels == 1usize {
                    parent = tall
                    if append_right {
                        left = child
                        pos = at
                    } else {
                        right = child
                        let count = (*parent).len
                        copy_entries(node_entry(parent, 0usize), node_entry(parent, 1usize), count)
                        copy_links((*parent).children, (*parent).children.add(1usize), count + 1usize)
                    }
                    set_child(parent, pos, left)
                    set_child(parent, pos + 1usize, right)
                    (*parent).len += 1usize
                    break
                }
                if (*child).len == max_entries() {
                    let sibling = self.join_node(a, (*child).leaf)
                    split_into(tall, at, sibling)
                    if append_right { at += 1usize }
                    child = node_child(tall, at)
                }
                tall = child
                levels -= 1usize
            }
        }
        core.ptr.write(node_entry(parent, pos), middle)
        other.root = null_node<K, V>()
        other.len = 0usize
        self.root = root
        self.len = total
        var detached = null_node<K, V>()
        if (*left).len < min_entries() || (*right).len < min_entries() {
            if (*left).len + (*right).len + 1usize <= max_entries() {
                detached = self.merge_children(parent, pos)
            } else {
                if (*left).len < min_entries() {
                    while (*left).len < min_entries() { borrow_right(parent, pos) }
                } else {
                    while (*right).len < min_entries() { borrow_left(parent, pos + 1usize) }
                }
            }
        }
        recount_path(parent)
        self.rebalance(parent)
        if detached != null_node<K, V>() { free_node<K, V, A>(a, detached) }
    }

    unsafe fn join_node(a: ptr<mut A>, leaf: bool): ptr<mut Node<K, V>> {
        match capture alloc_node<K, V, A>(a, leaf) {
            success(node) => node,
            failure(_) => handle_alloc_error(layout_of<Node<K, V>>())
        }
    }

    pub mut fn append(mut other: SortedMap<K, V, A>): Unit {
        if other.len == 0usize { return () }
        if self.a.is_compatible(read other.a) {
            if self.len == 0usize {
                self.root = other.root
                self.len = other.len
                other.root = null_node<K, V>()
                other.len = 0usize
                return ()
            }
            let separated = unsafe {
                let low = first_pos(self.root)
                let high = last_pos(self.root)
                let other_low = first_pos(other.root)
                let other_high = last_pos(other.root)
                if (*node_entry(high.0, high.1)).key.cmp((*node_entry(other_low.0, other_low.1)).key).is_lt() {
                    present(false)
                } else if (*node_entry(other_high.0, other_high.1)).key.cmp((*node_entry(low.0, low.1)).key).is_lt() {
                    present(true)
                } else { none }
            }
            match separated {
                present(other_first) => {
                    unsafe { self.join_disjoint(mut other, other_first) }
                    return ()
                },
                none => {}
            }
            let total = self.len + other.len
            var plan = super.vec.with_capacity<u8>(total)
            var left = unsafe { first_pos(self.root) }
            var right = unsafe { first_pos(other.root) }
            var duplicates = 0usize
            unsafe {
                while left.0 != null_node<K, V>() && right.0 != null_node<K, V>() {
                    let order = (*node_entry(left.0, left.1)).key.cmp((*node_entry(right.0, right.1)).key)
                    if order.is_eq() {
                        plan.push(2u8)
                        duplicates += 1usize
                        left = successor(left.0, left.1)
                        right = successor(right.0, right.1)
                    } else if order.is_lt() {
                        plan.push(0u8)
                        left = successor(left.0, left.1)
                    } else {
                        plan.push(1u8)
                        right = successor(right.0, right.1)
                    }
                }
                while left.0 != null_node<K, V>() {
                    plan.push(0u8)
                    left = successor(left.0, left.1)
                }
                while right.0 != null_node<K, V>() {
                    plan.push(1u8)
                    right = successor(right.0, right.1)
                }
            }
            let len = total - duplicates
            var entries = super.vec.with_capacity<Bucket<K, V>>(len)
            var discarded = super.vec.with_capacity<Bucket<K, V>>(duplicates)
            var height = 0usize
            while bulk_capacity(height) < len { height += 1usize }
            let needed = bulk_node_counts(len, height)
            let available_left = unsafe { tree_node_counts(self.root) }
            let available_right = unsafe { tree_node_counts(other.root) }
            var pool = BulkNodes(core.ptr.from_mut(self.a), null_node<K, V>(), null_node<K, V>(), null_node<K, V>())
            var kind = 0usize
            while kind < 2usize {
                var available = if kind == 0usize {
                    available_left.0 + available_right.0
                } else { available_left.1 + available_right.1 }
                let required = if kind == 0usize { needed.0 } else { needed.1 }
                while available < required {
                    let node = match capture unsafe { alloc_node<K, V, A>(pool.a, kind == 0usize) } {
                        success(node) => node,
                        failure(_) => handle_alloc_error(layout_of<Node<K, V>>())
                    }
                    unsafe { pool.add(node) }
                    available += 1usize
                }
                kind += 1usize
            }
            unsafe {
                left = first_pos(self.root)
                right = first_pos(other.root)
                for step in read plan {
                    if *step == 0u8 {
                        let at = left
                        left = successor(left.0, left.1)
                        entries.push(core.ptr.`read`(node_entry(at.0, at.1)))
                    } else if *step == 1u8 {
                        let at = right
                        right = successor(right.0, right.1)
                        entries.push(core.ptr.`read`(node_entry(at.0, at.1)))
                    } else {
                        let l = left
                        let r = right
                        left = successor(left.0, left.1)
                        right = successor(right.0, right.1)
                        let stored = core.ptr.`read`(node_entry(l.0, l.1))
                        let donor = core.ptr.`read`(node_entry(r.0, r.1))
                        entries.push(Bucket(stored.key, donor.value))
                        discarded.push(Bucket(donor.key, stored.value))
                    }
                }
                let left_root = self.root
                let right_root = other.root
                self.root = null_node<K, V>()
                self.len = 0usize
                other.root = null_node<K, V>()
                other.len = 0usize
                pool.collect(left_root)
                pool.collect(right_root)
                self.root = pool.build(len, height, mut entries)
                self.len = len
            }
            pool.run()
            return ()
        }
        while true {
            match take other.pop_first() {
                present(entry) => { let _ = self.insert(take entry.0, take entry.1) },
                none => { break }
            }
        }
    }
}

// An entry owns its lookup key and exclusively borrows the map until consumed.
// Occupied node positions remain stable while that loan prevents map mutation.
pub type OccupiedEntry<region r, K, V, A: Allocator = Global> {
    map: mut SortedMap<K, V, A> from r
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
    pub mut fn entry(take key: K): Entry<region self, K, V, A> {
        match unsafe { find_slot(self.root, key) } {
            present(at) => Entry.Occupied(OccupiedEntry(mut self, at.0, at.1)),
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
    pub mut fn insert(take value: V): V {
        let slot = unsafe {
            core.ptr.from_mut((*node_entry(self.node, self.index)).value)
        }
        unsafe { core.ptr.replace(slot, value) }
    }
    pub take fn into_mut(): mut V from r {
        unsafe { mut (*node_entry(self.node, self.index)).value }
    }
    pub take fn remove(): V {
        unsafe { self.map.take_entry(self.node, self.index).value }
    }
}

extend<region r, K: Ord, V, A: Allocator> VacantEntry<region r, K, V, A> {
    pub fn key(): read K from self { read self.key }
    pub take fn insert(take value: V): mut V from r {
        let outcome = capture self.map.try_insert_with_slot(take self.key, take value)
        match take outcome {
            success(result) => unsafe { mut (*node_entry(result.1, result.2)).value },
            failure(_) => handle_alloc_error(layout_of<Node<K, V>>())
        }
    }
}
extend<region r, K: Ord + fmt.Debug, V: fmt.Debug, A: Allocator> OccupiedEntry<region r, K, V, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("OccupiedEntry")
        try debug.field("key", self.key())
        try debug.field("value", self.get())
        try debug.finish_non_exhaustive()
    }
}
extend<region r, K: Ord + fmt.Debug, V, A: Allocator> VacantEntry<region r, K, V, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("VacantEntry")
        try debug.field("key", self.key())
        try debug.finish_non_exhaustive()
    }
}

extend<region r, K: Ord, V, A: Allocator> Entry<region r, K, V, A> {
    pub fn key(): read K from self {
        match self {
            Entry.Occupied(entry) => entry.key(),
            Entry.Vacant(entry) => entry.key()
        }
    }
    pub take fn or_insert(take value: V): mut V from r {
        match take self {
            Entry.Occupied(entry) => entry.into_mut(),
            Entry.Vacant(entry) => entry.insert(take value)
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
                entry.insert(take value)
            }
        }
    }
    pub take fn insert_entry(take value: V): OccupiedEntry<region r, K, V, A> {
        match take self {
            Entry.Occupied(entry) => {
                var occupied = entry
                let _old = occupied.insert(take value)
                occupied
            },
            Entry.Vacant(entry) => {
                let outcome = capture entry.map.try_insert_with_slot(take entry.key, take value)
                match take outcome {
                    success(result) => OccupiedEntry(entry.map, result.1, result.2),
                    failure(_) => handle_alloc_error(layout_of<Node<K, V>>())
                }
            }
        }
    }
    pub take fn and_modify<F: take fn(mut V): Unit>(take modify: F): Entry<region r, K, V, A> {
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

extend<region r, K: Ord + fmt.Debug, V: fmt.Debug, A: Allocator> Entry<region r, K, V, A> implements fmt.Debug {
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
                try K.(fmt.Debug).fmt(entry.key(), mut f)
                try f.write_str(")")
            }
        }
    }
}

pub type SortedSet<K, A: Allocator = Global> { map: SortedMap<K, Unit, A> }

pub fn set_new_in<K, A: Allocator>(take a: A): SortedSet<K, A> { SortedSet(new_in<K, Unit, A>(take a)) }
pub fn set_new<K>(): SortedSet<K> { SortedSet(new<K, Unit>()) }

extend<K: Ord, A: Allocator> SortedSet<K, A> {
    pub fn len(): usize { self.map.len() }
    pub fn is_empty(): bool { self.map.is_empty() }
    pub fn contains<Q: Ord + unsized>(read key: Q): bool where K: KeyView<Q> { self.map.contains_key(key) }
    pub fn get<Q: Ord + unsized>(read key: Q): (read K from self)? where K: KeyView<Q> {
        match self.map.get_key_value(key) {
            present(entry) => present(entry.0),
            none => none
        }
    }
    pub mut fn insert(take key: K): bool {
        match self.map.insert(take key, ()) { present(_) => false, none => true }
    }
    pub mut fn remove<Q: Ord + unsized>(read key: Q): bool where K: KeyView<Q> {
        match self.map.remove(key) { present(_) => true, none => false }
    }
    pub mut fn `take`<Q: Ord + unsized>(read key: Q): K? where K: KeyView<Q> {
        match take self.map.remove_entry(key) {
            present(entry) => present(entry.0),
            none => none
        }
    }
    pub mut fn replace(take value: K): K? {
        match unsafe { find_slot(self.map.root, value) } {
            present(at) => {
                let entry = unsafe { node_entry(at.0, at.1) }
                // The exclusive receiver keeps this live entry stable; an
                // equal replacement preserves its tree position.
                let key_slot = unsafe { core.ptr.from_mut((*entry).key) }
                present(unsafe { core.ptr.replace(key_slot, value) })
            },
            none => {
                let _old = self.map.insert(take value, ())
                none
            }
        }
    }
    pub fn first(): (read K from self)? { self.map.first_key() }
    pub fn last(): (read K from self)? { self.map.last_key() }
    pub mut fn pop_first(): K? {
        match take self.map.pop_first() {
            present(entry) => present(entry.0),
            none => none
        }
    }
    pub mut fn pop_last(): K? {
        match take self.map.pop_last() {
            present(entry) => present(entry.0),
            none => none
        }
    }
    pub mut fn split_off(read key: K): SortedSet<K, A> where A: Clone {
        SortedSet(self.map.split_off(key))
    }
    pub mut fn extract_if<R: RangeBounds<K>, F: mut fn(read K): bool>(
        take bounds: R, take predicate: F
    ): SetExtractIf<region self, K, A, R, F> where K: KeyView<K> {
        let positions = range_positions(
            self.map.root,
            R.(RangeBounds<K>).start_bound(read bounds),
            R.(RangeBounds<K>).end_bound(read bounds)
        )
        SetExtractIf(mut self, predicate, bounds, positions.0.0, positions.0.1, positions.1.0, positions.1.1)
    }
    pub mut fn retain<F: mut fn(read K): bool>(take predicate: F): Unit {
        var keep = predicate
        var at = unsafe { first_pos(self.map.root) }
        while at.0 != null_node<K, Unit>() {
            let entry = unsafe { node_entry(at.0, at.1) }
            if keep(unsafe { read (*entry).key }) {
                at = unsafe { successor(at.0, at.1) }
            } else {
                at = {
                    let removed = unsafe { self.map.take_entry(at.0, at.1) }
                    unsafe { bound_pos(self.map.root, read removed.key) }
                }
            }
        }
    }
    pub fn range<Q: Ord + unsized, R: RangeBounds<Q>>(
        take bounds: R
    ): KeyRange<region self, K, Unit, A> where K: KeyView<Q> {
        self.map.range<Q, R>(take bounds)
    }
}

pub type SortedSetAlgebra<region r, K, A: Allocator> {
    left_iter: Keys<region r, K, Unit, A>
    right_iter: Keys<region r, K, Unit, A>
    left: (read K from r)?
    right: (read K from r)?
    mode: u8
}
extend<region r, K, A: Allocator> SortedSetAlgebra<region r, K, A> implements Clone {
    fn clone(): SortedSetAlgebra<region r, K, A> {
        SortedSetAlgebra(
            self.left_iter.clone(),
            self.right_iter.clone(),
            self.left,
            self.right,
            self.mode
        )
    }
}
extend<region r, K: Ord, A: Allocator> SortedSetAlgebra<region r, K, A> implements Iterator {
    type Item = read K from r
    mut fn next(): (read K from r)? {
        while true {
            if self.left.is_none() { self.left = self.left_iter.next() }
            if self.right.is_none() { self.right = self.right_iter.next() }
            match self.left {
                present(left) => match self.right {
                    present(right) => {
                        let order = left.cmp(right)
                        if order.is_lt() {
                            self.left = none
                            if self.mode != 1u8 { return present(left) }
                        } else if order.is_gt() {
                            self.right = none
                            if self.mode == 0u8 || self.mode == 3u8 { return present(right) }
                        } else {
                            self.left = none
                            self.right = none
                            if self.mode == 0u8 || self.mode == 1u8 { return present(left) }
                        }
                    },
                    none => {
                        self.left = none
                        if self.mode != 1u8 { return present(left) }
                        return none
                    },
                },
                none => match self.right {
                    present(right) => {
                        self.right = none
                        if self.mode == 0u8 || self.mode == 3u8 { return present(right) }
                        return none
                    },
                    none => { return none }
                }
            }
        }
        none
    }
}

extend<region r, K: Ord + fmt.Debug, A: Allocator> SortedSetAlgebra<region r, K, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        let name = match self.mode {
            0u8 => "Union",
            1u8 => "Intersection",
            2u8 => "Difference",
            _ => "SymmetricDifference"
        }
        var debug = try f.debug_struct(name)
        try debug.field("left_iter", read self.left_iter)
        try debug.field("right_iter", read self.right_iter)
        try debug.field("left", read self.left)
        try debug.field("right", read self.right)
        try debug.finish()
    }
}

extend<K: Ord, A: Allocator> SortedSet<K, A> {
    pub fn `union`(read other: SortedSet<K, A> from self): SortedSetAlgebra<region self, K, A> {
        SortedSetAlgebra(self.iter(), other.iter(), none, none, 0u8)
    }
    pub fn intersection(read other: SortedSet<K, A> from self): SortedSetAlgebra<region self, K, A> {
        SortedSetAlgebra(self.iter(), other.iter(), none, none, 1u8)
    }
    pub fn difference(read other: SortedSet<K, A> from self): SortedSetAlgebra<region self, K, A> {
        SortedSetAlgebra(self.iter(), other.iter(), none, none, 2u8)
    }
    pub fn symmetric_difference(read other: SortedSet<K, A> from self): SortedSetAlgebra<region self, K, A> {
        SortedSetAlgebra(self.iter(), other.iter(), none, none, 3u8)
    }
    pub fn is_subset(read other: SortedSet<K, A>): bool {
        var iter = self.iter()
        while true {
            match iter.next() {
                present(key) => { if !other.contains(key) { return false } },
                none => { return true }
            }
        }
        true
    }
    pub fn is_superset(read other: SortedSet<K, A>): bool {
        var iter = other.iter()
        while true {
            match iter.next() {
                present(key) => { if !self.contains(key) { return false } },
                none => { return true }
            }
        }
        true
    }
    pub fn is_disjoint(read other: SortedSet<K, A>): bool {
        var iter = self.iter()
        while true {
            match iter.next() {
                present(key) => { if other.contains(key) { return false } },
                none => { return true }
            }
        }
        true
    }
}

// Borrowed in-order iteration over the entries. `front` and `back` are the
// next positions to yield from each end and `left` entries remain, so the two
// ends never cross.
pub type EntryIter<region r, K, V, A: Allocator> {
    map: (read SortedMap<K, V, A> from r)?
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
    fn size_hint(): (usize, usize?) { (self.left, present(self.left)) }
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
extend<region r, K, V, A: Allocator> EntryIter<region r, K, V, A> implements ExactSizeIterator {}
extend<region r, K, V, A: Allocator> EntryIter<region r, K, V, A> implements Clone {
    fn clone(): EntryIter<region r, K, V, A> {
        EntryIter(self.map, self.front_node, self.front_idx, self.back_node, self.back_idx, self.left)
    }
}
extend<region r, K, V, A: Allocator> EntryIter<region r, K, V, A> implements Default {
    // The absent map and zero count keep the null cursors out of both ends.
    static fn default(): EntryIter<region r, K, V, A> {
        EntryIter(none, null_node<K, V>(), 0usize, null_node<K, V>(), 0usize, 0usize)
    }
}
extend<region r, K: fmt.Debug, V: fmt.Debug, A: Allocator> EntryIter<region r, K, V, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("Iter(")
        try f.debug_open("{")
        var node = self.front_node
        var idx = self.front_idx
        var left = self.left
        var first = true
        while left != 0usize {
            let entry = unsafe { node_entry(node, idx) }
            try f.debug_item_start(first)
            try K.(fmt.Debug).fmt(unsafe { read (*entry).key }, mut f)
            try f.write_str(": ")
            try V.(fmt.Debug).fmt(unsafe { read (*entry).value }, mut f)
            try f.debug_item_end()
            first = false
            left -= 1usize
            if left != 0usize {
                let after = unsafe { successor(node, idx) }
                node = after.0
                idx = after.1
            }
        }
        try f.debug_close("}", self.left == 0usize)
        try f.write_str(")")
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
extend<region r, K, V, A: Allocator> KeyRange<region r, K, V, A> implements Clone {
    fn clone(): KeyRange<region r, K, V, A> {
        KeyRange(self.map, self.node, self.idx, self.end_node, self.end_idx)
    }
}

// Mutably iterates values in a half-open range without exposing mutable keys.
pub type RangeMut<region r, K, V, A: Allocator> {
    map: (mut SortedMap<K, V, A> from r)?
    front_node: ptr<mut Node<K, V>>
    front_idx: usize
    back_node: ptr<mut Node<K, V>>
    back_idx: usize
    done: bool
}
extend<region r, K, V, A: Allocator> RangeMut<region r, K, V, A> implements Iterator {
    type Item = mut V from r
    mut fn next(): (mut V from r)? {
        if self.done { return none }
        let at = unsafe { node_entry(self.front_node, self.front_idx) }
        if self.front_node == self.back_node && self.front_idx == self.back_idx {
            self.done = true
        } else {
            let after = unsafe { successor(self.front_node, self.front_idx) }
            self.front_node = after.0
            self.front_idx = after.1
        }
        present(unsafe { mut (*at).value })
    }
}
extend<region r, K, V, A: Allocator> RangeMut<region r, K, V, A> implements BidirectionalIterator {
    mut fn next_back(): (mut V from r)? {
        if self.done { return none }
        let at = unsafe { node_entry(self.back_node, self.back_idx) }
        if self.front_node == self.back_node && self.front_idx == self.back_idx {
            self.done = true
        } else {
            let before = unsafe { predecessor(self.back_node, self.back_idx) }
            self.back_node = before.0
            self.back_idx = before.1
        }
        present(unsafe { mut (*at).value })
    }
}
extend<region r, K, V, A: Allocator> RangeMut<region r, K, V, A> implements Default {
    static fn default(): RangeMut<region r, K, V, A> {
        RangeMut(none, null_node<K, V>(), 0usize, null_node<K, V>(), 0usize, true)
    }
}
extend<region r, K, V, A: Allocator> RangeMut<region r, K, V, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("RangeMut")
        try debug.finish_non_exhaustive()
    }
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

pub type MapExtractIf<region r, K, V, A: Allocator, R, F> {
    map: mut SortedMap<K, V, A> from r
    predicate: F
    bounds: R
    node: ptr<mut Node<K, V>>
    index: usize
    end_node: ptr<mut Node<K, V>>
    end_index: usize
}
extend<region r, K: Ord, V, A: Allocator, R: RangeBounds<K>, F: mut fn(read K, mut V): bool> MapExtractIf<region r, K, V, A, R, F> implements Iterator {
    type Item = (K, V)
    mut fn next(): (K, V)? {
        while self.node != self.end_node || self.index != self.end_index {
            if self.node == null_node<K, V>() { return none }
            let entry = unsafe { node_entry(self.node, self.index) }
            if self.predicate(unsafe { read (*entry).key }, unsafe { mut (*entry).value }) {
                let node = self.node
                let index = self.index
                self.node = null_node<K, V>()
                let removed = unsafe { self.map.take_entry(node, index) }
                let next = unsafe { bound_pos(self.map.root, read removed.key) }
                let positions = range_positions(
                    self.map.root,
                    R.(RangeBounds<K>).start_bound(read self.bounds),
                    R.(RangeBounds<K>).end_bound(read self.bounds)
                )
                self.node = next.0
                self.index = next.1
                self.end_node = positions.1.0
                self.end_index = positions.1.1
                return present((removed.key, removed.value))
            }
            let next = unsafe { successor(self.node, self.index) }
            self.node = next.0
            self.index = next.1
        }
        none
    }
}
extend<region r, K, V, A: Allocator, R, F> MapExtractIf<region r, K, V, A, R, F> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("ExtractIf")
        try debug.field("index", self.index)
        try debug.finish_non_exhaustive()
    }
}

pub type SetExtractIf<region r, K, A: Allocator, R, F> {
    set: mut SortedSet<K, A> from r
    predicate: F
    bounds: R
    node: ptr<mut Node<K, Unit>>
    index: usize
    end_node: ptr<mut Node<K, Unit>>
    end_index: usize
}
extend<region r, K: Ord, A: Allocator, R: RangeBounds<K>, F: mut fn(read K): bool> SetExtractIf<region r, K, A, R, F> implements Iterator {
    type Item = K
    mut fn next(): K? {
        while self.node != self.end_node || self.index != self.end_index {
            if self.node == null_node<K, Unit>() { return none }
            let entry = unsafe { node_entry(self.node, self.index) }
            if self.predicate(unsafe { read (*entry).key }) {
                let node = self.node
                let index = self.index
                self.node = null_node<K, Unit>()
                let removed = unsafe { self.set.map.take_entry(node, index) }
                let next = unsafe { bound_pos(self.set.map.root, read removed.key) }
                let positions = range_positions(
                    self.set.map.root,
                    R.(RangeBounds<K>).start_bound(read self.bounds),
                    R.(RangeBounds<K>).end_bound(read self.bounds)
                )
                self.node = next.0
                self.index = next.1
                self.end_node = positions.1.0
                self.end_index = positions.1.1
                return present(removed.key)
            }
            let next = unsafe { successor(self.node, self.index) }
            self.node = next.0
            self.index = next.1
        }
        none
    }
}
extend<region r, K, A: Allocator, R, F> SetExtractIf<region r, K, A, R, F> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("ExtractIf")
        try debug.field("index", self.index)
        try debug.finish_non_exhaustive()
    }
}

// Iteration is in ascending key order.
extend<K, V, A: Allocator> SortedMap<K, V, A> implements Iterable {
    type Item = Bucket<K, V>
    type Iter<region r> = EntryIter<region r, K, V, A>
    fn iter<region r>(receiver read self: Self from r): EntryIter<region r, K, V, A> {
        let first = unsafe { first_pos(self.root) }
        let last = unsafe { last_pos(self.root) }
        EntryIter(present(read self), first.0, first.1, last.0, last.1, self.len)
    }
}
extend<K, A: Allocator> SortedSet<K, A> implements Iterable {
    type Item = K
    type Iter<region r> = Keys<region r, K, Unit, A>
    fn iter<region r>(receiver read self: Self from r): Keys<region r, K, Unit, A> {
        let first = unsafe { first_pos(self.map.root) }
        let last = unsafe { last_pos(self.map.root) }
        Keys(EntryIter(present(read self.map), first.0, first.1, last.0, last.1, self.map.len))
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
    back_node: ptr<mut Node<K, V>>
    back_idx: usize
    left: usize
    drop {
        var remaining = TreeDrop(core.ptr.from_mut(self.a), self.root, self.node, self.idx, self.left)
        self.root = null_node<K, V>()
        self.left = 0usize
        remaining.run()
    }
}
extend<K, V, A: Allocator> SortedMap<K, V, A> implements OwnedIterable {
    type Item = Bucket<K, V>
    type IntoIter = MapIntoIter<K, V, A>
    fn into_iter(receiver take self: Self): MapIntoIter<K, V, A> {
        unsafe {
            let root = self.root
            let n = self.len
            let first = first_pos(root)
            let last = last_pos(root)
            let a = core.ptr.`read`(core.ptr.from_ref(self.a))
            core.mem.forget(take self)
            MapIntoIter(root, a, first.0, first.1, last.0, last.1, n)
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
    fn size_hint(): (usize, usize?) { (self.left, present(self.left)) }
}
extend<K, V, A: Allocator> MapIntoIter<K, V, A> implements BidirectionalIterator {
    mut fn next_back(): Bucket<K, V>? {
        if self.left == 0usize { return none }
        let n = self.back_node
        let i = self.back_idx
        self.left -= 1usize
        if self.left != 0usize {
            let before = unsafe { predecessor(n, i) }
            self.back_node = before.0
            self.back_idx = before.1
        }
        present(unsafe { core.ptr.`read`(node_entry(n, i)) })
    }
}
extend<K, V, A: Allocator> MapIntoIter<K, V, A> implements ExactSizeIterator {}
extend<K: fmt.Debug, V: fmt.Debug, A: Allocator> MapIntoIter<K, V, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.debug_open("{")
        var node = self.node
        var idx = self.idx
        var left = self.left
        var first = true
        while left != 0usize {
            let entry = unsafe { node_entry(node, idx) }
            try f.debug_item_start(first)
            try K.(fmt.Debug).fmt(unsafe { read (*entry).key }, mut f)
            try f.write_str(": ")
            try V.(fmt.Debug).fmt(unsafe { read (*entry).value }, mut f)
            try f.debug_item_end()
            first = false
            left -= 1usize
            if left != 0usize {
                let after = unsafe { successor(node, idx) }
                node = after.0
                idx = after.1
            }
        }
        try f.debug_close("}", self.left == 0usize)
    }
}
extend<K, V, A: Allocator + Default> MapIntoIter<K, V, A> implements Default {
    static fn default(): MapIntoIter<K, V, A> {
        MapIntoIter(
            null_node<K, V>(),
            A.(Default).default(),
            null_node<K, V>(),
            0usize,
            null_node<K, V>(),
            0usize,
            0usize
        )
    }
}
extend<K, V, A: Allocator> SortedMap<K, V, A> {
    pub take fn into_keys(): IntoKeys<K, V, A> { IntoKeys(self.into_iter()) }
    pub take fn into_values(): IntoValues<K, V, A> { IntoValues(self.into_iter()) }
}
pub type IntoKeys<K, V, A: Allocator> { inner: MapIntoIter<K, V, A> }
extend<K, V, A: Allocator> IntoKeys<K, V, A> implements Iterator {
    type Item = K
    mut fn next(): K? {
        match take self.inner.next() {
            present(entry) => present(entry.key),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}
extend<K, V, A: Allocator> IntoKeys<K, V, A> implements BidirectionalIterator {
    mut fn next_back(): K? {
        match take self.inner.next_back() {
            present(entry) => present(entry.key),
            none => none
        }
    }
}
extend<K, V, A: Allocator> IntoKeys<K, V, A> implements ExactSizeIterator {}
extend<K, V, A: Allocator + Default> IntoKeys<K, V, A> implements Default {
    static fn default(): IntoKeys<K, V, A> {
        IntoKeys(MapIntoIter<K, V, A>.(Default).default())
    }
}
pub type IntoValues<K, V, A: Allocator> { inner: MapIntoIter<K, V, A> }
extend<K, V, A: Allocator> IntoValues<K, V, A> implements Iterator {
    type Item = V
    mut fn next(): V? {
        match take self.inner.next() {
            present(entry) => present(entry.value),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}
extend<K, V, A: Allocator> IntoValues<K, V, A> implements BidirectionalIterator {
    mut fn next_back(): V? {
        match take self.inner.next_back() {
            present(entry) => present(entry.value),
            none => none
        }
    }
}
extend<K, V, A: Allocator> IntoValues<K, V, A> implements ExactSizeIterator {}
extend<K, V, A: Allocator + Default> IntoValues<K, V, A> implements Default {
    static fn default(): IntoValues<K, V, A> {
        IntoValues(MapIntoIter<K, V, A>.(Default).default())
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
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}
extend<K, A: Allocator> SetIntoIter<K, A> implements BidirectionalIterator {
    mut fn next_back(): K? {
        match take self.inner.next_back() {
            present(pair) => present(pair.key),
            none => none
        }
    }
}
extend<K, A: Allocator> SetIntoIter<K, A> implements ExactSizeIterator {}
extend<K: fmt.Debug, A: Allocator> SetIntoIter<K, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.debug_open("{")
        var node = self.inner.node
        var idx = self.inner.idx
        var left = self.inner.left
        while left != 0usize {
            let entry = unsafe { node_entry(node, idx) }
            try f.debug_item_start(left == self.inner.left)
            try K.(fmt.Debug).fmt(unsafe { read (*entry).key }, mut f)
            try f.debug_item_end()
            left -= 1usize
            if left != 0usize {
                let after = unsafe { successor(node, idx) }
                node = after.0
                idx = after.1
            }
        }
        try f.debug_close("}", self.inner.left == 0usize)
    }
}
extend<K, A: Allocator + Default> SetIntoIter<K, A> implements Default {
    static fn default(): SetIntoIter<K, A> {
        SetIntoIter(MapIntoIter<K, Unit, A>.(Default).default())
    }
}
extend<K, A: Allocator> SortedSet<K, A> implements OwnedIterable {
    type Item = K
    type IntoIter = SetIntoIter<K, A>
    fn into_iter(receiver take self: Self): SetIntoIter<K, A> {
        SetIntoIter(self.map.into_iter())
    }
}

// Mutable iteration returns an immutable key and exclusive value view in key
// order, without exposing mutation that could break the tree's ordering.
// The exclusive map borrow keeps links stable; successor advancement and the
// remaining count ensure each entry slot is issued at most once. An empty
// default has no map and never dereferences its null cursors.
pub type IterMut<region r, K, V, A: Allocator> {
    map: (mut SortedMap<K, V, A> from r)?
    front_node: ptr<mut Node<K, V>>
    front_idx: usize
    back_node: ptr<mut Node<K, V>>
    back_idx: usize
    left: usize
}
extend<region r, K, V, A: Allocator> IterMut<region r, K, V, A> implements Iterator {
    type Item = (read K from r, mut V from r)
    mut fn next(): (read K from r, mut V from r)? {
        if self.left == 0usize { return none }
        let at = unsafe { node_entry(self.front_node, self.front_idx) }
        self.left -= 1usize
        if self.left != 0usize {
            let after = unsafe { successor(self.front_node, self.front_idx) }
            self.front_node = after.0
            self.front_idx = after.1
        }
        present(unsafe { (read (*at).key, mut (*at).value) })
    }
    fn size_hint(): (usize, usize?) { (self.left, present(self.left)) }
}
extend<region r, K, V, A: Allocator> IterMut<region r, K, V, A> implements BidirectionalIterator {
    mut fn next_back(): (read K from r, mut V from r)? {
        if self.left == 0usize { return none }
        let at = unsafe { node_entry(self.back_node, self.back_idx) }
        self.left -= 1usize
        if self.left != 0usize {
            let before = unsafe { predecessor(self.back_node, self.back_idx) }
            self.back_node = before.0
            self.back_idx = before.1
        }
        present(unsafe { (read (*at).key, mut (*at).value) })
    }
}
extend<region r, K, V, A: Allocator> IterMut<region r, K, V, A> implements ExactSizeIterator {}
extend<region r, K, V, A: Allocator> IterMut<region r, K, V, A> implements Default {
    static fn default(): IterMut<region r, K, V, A> {
        IterMut(none, null_node<K, V>(), 0usize, null_node<K, V>(), 0usize, 0usize)
    }
}
extend<region r, K: fmt.Debug, V: fmt.Debug, A: Allocator> IterMut<region r, K, V, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("IterMut(")
        try f.debug_open("{")
        var node = self.front_node
        var idx = self.front_idx
        var left = self.left
        var first = true
        while left != 0usize {
            let entry = unsafe { node_entry(node, idx) }
            try f.debug_item_start(first)
            try K.(fmt.Debug).fmt(unsafe { read (*entry).key }, mut f)
            try f.write_str(": ")
            try V.(fmt.Debug).fmt(unsafe { read (*entry).value }, mut f)
            try f.debug_item_end()
            first = false
            left -= 1usize
            if left != 0usize {
                let after = unsafe { successor(node, idx) }
                node = after.0
                idx = after.1
            }
        }
        try f.debug_close("}", self.left == 0usize)
        try f.write_str(")")
    }
}
extend<K, V, A: Allocator> SortedMap<K, V, A> {
    pub mut fn iter_mut(): IterMut<region self, K, V, A> {
        let first = unsafe { first_pos(self.root) }
        let last = unsafe { last_pos(self.root) }
        let n = self.len
        IterMut(present(mut self), first.0, first.1, last.0, last.1, n)
    }
}

// Generic mutable iteration visits values only, in key order.
pub type ValuesMut<region r, K, V, A: Allocator> {
    map: (mut SortedMap<K, V, A> from r)?
    front_node: ptr<mut Node<K, V>>
    front_idx: usize
    back_node: ptr<mut Node<K, V>>
    back_idx: usize
    left: usize
}
extend<region r, K, V, A: Allocator> ValuesMut<region r, K, V, A> implements Iterator {
    type Item = mut V from r
    mut fn next(): (mut V from r)? {
        if self.left == 0usize { return none }
        let at = unsafe { node_entry(self.front_node, self.front_idx) }
        self.left -= 1usize
        if self.left != 0usize {
            let after = unsafe { successor(self.front_node, self.front_idx) }
            self.front_node = after.0
            self.front_idx = after.1
        }
        present(unsafe { mut (*at).value })
    }
    fn size_hint(): (usize, usize?) { (self.left, present(self.left)) }
}
extend<region r, K, V, A: Allocator> ValuesMut<region r, K, V, A> implements BidirectionalIterator {
    mut fn next_back(): (mut V from r)? {
        if self.left == 0usize { return none }
        let at = unsafe { node_entry(self.back_node, self.back_idx) }
        self.left -= 1usize
        if self.left != 0usize {
            let before = unsafe { predecessor(self.back_node, self.back_idx) }
            self.back_node = before.0
            self.back_idx = before.1
        }
        present(unsafe { mut (*at).value })
    }
}
extend<region r, K, V, A: Allocator> ValuesMut<region r, K, V, A> implements ExactSizeIterator {}
extend<region r, K, V, A: Allocator> ValuesMut<region r, K, V, A> implements Default {
    // The absent map and zero count make the null cursor unreachable.
    static fn default(): ValuesMut<region r, K, V, A> {
        ValuesMut(none, null_node<K, V>(), 0usize, null_node<K, V>(), 0usize, 0usize)
    }
}
extend<region r, K, V: fmt.Debug, A: Allocator> ValuesMut<region r, K, V, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("ValuesMut(")
        try f.debug_open("[")
        var node = self.front_node
        var idx = self.front_idx
        var left = self.left
        var first = true
        while left != 0usize {
            let entry = unsafe { node_entry(node, idx) }
            try f.debug_item_start(first)
            try V.(fmt.Debug).fmt(unsafe { read (*entry).value }, mut f)
            try f.debug_item_end()
            first = false
            left -= 1usize
            if left != 0usize {
                let after = unsafe { successor(node, idx) }
                node = after.0
                idx = after.1
            }
        }
        try f.debug_close("]", self.left == 0usize)
        try f.write_str(")")
    }
}
// Borrowed iterators over the keys or the values only.
pub type Keys<region r, K, V, A: Allocator> { inner: EntryIter<region r, K, V, A> }
extend<region r, K, V, A: Allocator> Keys<region r, K, V, A> implements Iterator {
    type Item = read K from r
    mut fn next(): (read K from r)? {
        match self.inner.next() { present(e) => present(read e.key), none => none }
    }
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}
extend<region r, K, V, A: Allocator> Keys<region r, K, V, A> implements Clone {
    fn clone(): Keys<region r, K, V, A> { Keys(self.inner.clone()) }
}
extend<region r, K, V, A: Allocator> Keys<region r, K, V, A> implements Default {
    static fn default(): Keys<region r, K, V, A> {
        Keys(EntryIter<region r, K, V, A>.(Default).default())
    }
}
extend<region r, K: fmt.Debug, V, A: Allocator> Keys<region r, K, V, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("Keys(")
        try f.debug_open("[")
        var node = self.inner.front_node
        var idx = self.inner.front_idx
        var left = self.inner.left
        var first = true
        while left != 0usize {
            let entry = unsafe { node_entry(node, idx) }
            try f.debug_item_start(first)
            try K.(fmt.Debug).fmt(unsafe { read (*entry).key }, mut f)
            try f.debug_item_end()
            first = false
            left -= 1usize
            if left != 0usize {
                let after = unsafe { successor(node, idx) }
                node = after.0
                idx = after.1
            }
        }
        try f.debug_close("]", self.inner.left == 0usize)
        try f.write_str(")")
    }
}
extend<region r, K, V, A: Allocator> Keys<region r, K, V, A> implements ExactSizeIterator {}
extend<region r, K, V, A: Allocator> Keys<region r, K, V, A> implements BidirectionalIterator {
    mut fn next_back(): (read K from r)? {
        match self.inner.next_back() { present(e) => present(read e.key), none => none }
    }
}
pub type Values<region r, K, V, A: Allocator> { inner: EntryIter<region r, K, V, A> }
extend<region r, K, V, A: Allocator> Values<region r, K, V, A> implements Iterator {
    type Item = read V from r
    mut fn next(): (read V from r)? {
        match self.inner.next() { present(e) => present(read e.value), none => none }
    }
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}
extend<region r, K, V, A: Allocator> Values<region r, K, V, A> implements Clone {
    fn clone(): Values<region r, K, V, A> { Values(self.inner.clone()) }
}
extend<region r, K, V, A: Allocator> Values<region r, K, V, A> implements Default {
    static fn default(): Values<region r, K, V, A> {
        Values(EntryIter<region r, K, V, A>.(Default).default())
    }
}
extend<region r, K: Ord, A: Allocator> SortedSetAlgebra<region r, K, A> implements FusedIterator {}
extend<region r, K, V, A: Allocator> EntryIter<region r, K, V, A> implements FusedIterator {}
extend<region r, K, V, A: Allocator> RangeMut<region r, K, V, A> implements FusedIterator {}
extend<region r, K, V, A: Allocator> KeyRange<region r, K, V, A> implements FusedIterator {}
extend<region r, K: Ord, V, A: Allocator, R: RangeBounds<K>, F: mut fn(read K, mut V): bool> MapExtractIf<region r, K, V, A, R, F> implements FusedIterator {}
extend<region r, K: Ord, A: Allocator, R: RangeBounds<K>, F: mut fn(read K): bool> SetExtractIf<region r, K, A, R, F> implements FusedIterator {}
extend<K, V, A: Allocator> MapIntoIter<K, V, A> implements FusedIterator {}
extend<K, V, A: Allocator> IntoKeys<K, V, A> implements FusedIterator {}
extend<K, V, A: Allocator> IntoValues<K, V, A> implements FusedIterator {}
extend<K, A: Allocator> SetIntoIter<K, A> implements FusedIterator {}
extend<region r, K, V, A: Allocator> IterMut<region r, K, V, A> implements FusedIterator {}
extend<region r, K, V, A: Allocator> ValuesMut<region r, K, V, A> implements FusedIterator {}
extend<region r, K, V, A: Allocator> Keys<region r, K, V, A> implements FusedIterator {}
extend<region r, K, V, A: Allocator> Values<region r, K, V, A> implements FusedIterator {}
extend<region r, K, V: fmt.Debug, A: Allocator> Values<region r, K, V, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("Values(")
        try f.debug_open("[")
        var node = self.inner.front_node
        var idx = self.inner.front_idx
        var left = self.inner.left
        var first = true
        while left != 0usize {
            let entry = unsafe { node_entry(node, idx) }
            try f.debug_item_start(first)
            try V.(fmt.Debug).fmt(unsafe { read (*entry).value }, mut f)
            try f.debug_item_end()
            first = false
            left -= 1usize
            if left != 0usize {
                let after = unsafe { successor(node, idx) }
                node = after.0
                idx = after.1
            }
        }
        try f.debug_close("]", self.inner.left == 0usize)
        try f.write_str(")")
    }
}
extend<region r, K, V, A: Allocator> Values<region r, K, V, A> implements ExactSizeIterator {}
extend<region r, K, V, A: Allocator> Values<region r, K, V, A> implements BidirectionalIterator {
    mut fn next_back(): (read V from r)? {
        match self.inner.next_back() { present(e) => present(read e.value), none => none }
    }
}
extend<K, V, A: Allocator> SortedMap<K, V, A> {
    pub fn keys(): Keys<region self, K, V, A> {
        let first = unsafe { first_pos(self.root) }
        let last = unsafe { last_pos(self.root) }
        Keys(EntryIter(present(read self), first.0, first.1, last.0, last.1, self.len))
    }
    pub fn values(): Values<region self, K, V, A> {
        let first = unsafe { first_pos(self.root) }
        let last = unsafe { last_pos(self.root) }
        Values(EntryIter(present(read self), first.0, first.1, last.0, last.1, self.len))
    }
}
extend<K, V, A: Allocator> SortedMap<K, V, A> implements MutableIterable {
    type Item = V
    type IterMut<region r> = ValuesMut<region r, K, V, A>
    fn iter_mut<region r>(receiver mut self: Self from r): ValuesMut<region r, K, V, A> {
        let first = unsafe { first_pos(self.root) }
        let last = unsafe { last_pos(self.root) }
        let n = self.len
        ValuesMut(present(mut self), first.0, first.1, last.0, last.1, n)
    }
}
extend<K, V, A: Allocator> SortedMap<K, V, A> {
    pub mut fn values_mut(): ValuesMut<region self, K, V, A> {
        let first = unsafe { first_pos(self.root) }
        let last = unsafe { last_pos(self.root) }
        let n = self.len
        ValuesMut(present(mut self), first.0, first.1, last.0, last.1, n)
    }
}

// Safety: entries and children count exactly the initialized owned prefix of each raw array.
type CloneNodeGuard<K, V, A: Allocator> {
    a: ptr<mut A>
    node: ptr<mut Node<K, V>>
    entries: usize
    children: usize
    drop {
        if self.node != null_node<K, V>() {
            unsafe {
                var index = 0usize
                while index < self.children {
                    release_tree<K, V, A>(self.a, node_child(self.node, index), true)
                    index += 1usize
                }
                super.vec.drop_run((*self.node).entries, self.entries)
                free_node<K, V, A>(self.a, self.node)
            }
        }
    }
}

// Copies the subtree at n; the guard owns only initialized entries and child links.
unsafe fn clone_tree<K: Clone, V: Clone, A: Allocator>(a: ptr<mut A>, n: ptr<mut Node<K, V>>, parent: ptr<mut Node<K, V>>): ptr<mut Node<K, V>> {
    let twin = match capture alloc_node<K, V, A>(a, (*n).leaf) {
        success(c) => c,
        failure(_) => handle_alloc_error(layout_of<Node<K, V>>())
    }
    var guard = CloneNodeGuard(a, twin, 0usize, 0usize)
    (*twin).parent = parent
    let len = (*n).len
    var i = 0usize
    while i < len {
        let e = node_entry(n, i)
        core.ptr.write(node_entry(twin, i), Bucket((*e).key.clone(), (*e).value.clone()))
        guard.entries += 1usize
        i += 1usize
    }
    if !(*n).leaf {
        var j = 0usize
        while j <= len {
            *(*twin).children.add(j) = clone_tree<K, V, A>(a, node_child(n, j), twin)
            guard.children += 1usize
            j += 1usize
        }
    }
    (*twin).len = len
    (*twin).subtree_len = (*n).subtree_len
    guard.node = null_node<K, V>()
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
    fn eq(read other: SortedMap<K, V, A>): bool {
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
extend<K: Ord, V, A: Allocator, Q: Ord + unsized> SortedMap<K, V, A> implements core.ops.Index<Q> where K: KeyView<Q> {
    type Output = V
    fn index(read key: Q): read V from self {
        match self.get(key) {
            present(value) => value,
            none => super.alloc.panic_precondition()
        }
    }
}
// Lexicographic over `(key, value)` entries in key order.
extend<K: PartialOrd, V: PartialOrd, A: Allocator> SortedMap<K, V, A> implements PartialOrd {
    fn partial_cmp(read other: SortedMap<K, V, A>): Ordering? {
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
    fn cmp(read other: SortedMap<K, V, A>): Ordering {
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
    fn hash<H: Hasher>(mut state: H): Unit {
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
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
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
    mut fn extend<I: OwnedIterable<Item = (K, V)>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(pair) => { let old = self.insert(take pair.0, take pair.1) },
                none => { break }
            }
        }
    }
}
extend<K: Ord, V> SortedMap<K, V> implements FromItems<(K, V)> {
    static fn from_iter<I: OwnedIterable<Item = (K, V)>>(take items: I): SortedMap<K, V> {
        var out = new<K, V>()
        out.extend(take items)
        out
    }
}

extend<K: Ord, V, const N: usize> SortedMap<K, V> implements core.convert.From<[(K, V); N]> {
    static fn from(take items: [(K, V); N]): SortedMap<K, V> {
        var out = new<K, V>()
        for item in take items { let _ = out.insert(take item.0, take item.1) }
        out
    }
}

extend<K: Clone, A: Allocator + Clone> SortedSet<K, A> implements Clone {
    fn clone(): SortedSet<K, A> { SortedSet(self.map.clone()) }
}
extend<K: PartialEq, A: Allocator> SortedSet<K, A> implements PartialEq {
    fn eq(read other: SortedSet<K, A>): bool { self.map == other.map }
}
extend<K: Eq, A: Allocator> SortedSet<K, A> implements Eq {}
extend<K: PartialOrd, A: Allocator> SortedSet<K, A> implements PartialOrd {
    fn partial_cmp(read other: SortedSet<K, A>): Ordering? { self.map.partial_cmp(other.map) }
}
extend<K: Ord, A: Allocator> SortedSet<K, A> implements Ord {
    fn cmp(read other: SortedSet<K, A>): Ordering { self.map.cmp(other.map) }
}
extend<K: Hash, A: Allocator> SortedSet<K, A> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.map.hash(mut state) }
}
extend<K: fmt.Debug, A: Allocator> SortedSet<K, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
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
    mut fn extend<I: OwnedIterable<Item = K>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { let added = self.insert(take item) }, none => { break } }
        }
    }
}
extend<K: Ord> SortedSet<K> implements FromItems<K> {
    static fn from_iter<I: OwnedIterable<Item = K>>(take items: I): SortedSet<K> {
        var out = set_new<K>()
        out.extend(take items)
        out
    }
}

extend<K: Ord, const N: usize> SortedSet<K> implements core.convert.From<[K; N]> {
    static fn from(take items: [K; N]): SortedSet<K> {
        var out = set_new<K>()
        for item in take items { let _ = out.insert(take item) }
        out
    }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<K: Transferable, V: Transferable, A: Allocator + Transferable> SortedMap<K, V, A> implements Transferable {}
unsafe extend<K: Shareable, V: Shareable, A: Allocator + Shareable> SortedMap<K, V, A> implements Shareable {}

// Entry handles retain the exclusive map loan that stabilizes their node pointers.
unsafe extend<region r, K: Transferable, V: Transferable, A: Allocator + Transferable> Entry<region r, K, V, A> implements Transferable {}
unsafe extend<region r, K: Shareable, V: Shareable, A: Allocator + Shareable> Entry<region r, K, V, A> implements Shareable {}
// Read cursors share the retained map; transferring one requires shared-safe storage.
unsafe extend<region r, K: Shareable, V: Shareable, A: Allocator + Shareable> EntryIter<region r, K, V, A> implements Transferable {}
unsafe extend<region r, K: Shareable, V: Shareable, A: Allocator + Shareable> EntryIter<region r, K, V, A> implements Shareable {}
// Exclusive cursors retain the map loan and never revisit an already yielded entry.
unsafe extend<region r, K: Transferable, V: Transferable, A: Allocator + Transferable> IterMut<region r, K, V, A> implements Transferable {}
unsafe extend<region r, K: Shareable, V: Shareable, A: Allocator + Shareable> IterMut<region r, K, V, A> implements Shareable {}
// The consuming cursor exclusively owns its remaining entries, nodes and allocator.
unsafe extend<K: Transferable, V: Transferable, A: Allocator + Transferable> MapIntoIter<K, V, A> implements Transferable {}
unsafe extend<K: Shareable, V: Shareable, A: Allocator + Shareable> MapIntoIter<K, V, A> implements Shareable {}

extend<K: Ord, V, A: Allocator + Default> SortedMap<K, V, A> implements Default {
    static fn default(): SortedMap<K, V, A> { new_in(A.(Default).default()) }
}

extend<K: Ord, A: Allocator + Default> SortedSet<K, A> implements Default {
    static fn default(): SortedSet<K, A> { set_new_in(A.(Default).default()) }
}

extend<K: Ord, A: Allocator> SortedSet<K, A> {
    // Moves every element of `other` into `self`; `other` is left empty.
    pub mut fn append(mut other: SortedSet<K, A>): Unit {
        while true {
            match take other.pop_first() {
                present(key) => { let _ = self.insert(take key) },
                none => { break }
            }
        }
    }
    pub mut fn clear(): Unit { self.map.clear() }
}

// The operators build new sets from clones of the operands' elements, as the
// `&a | &b` forms of the baseline do.
extend<K: Ord + Clone, A: Allocator + Clone> SortedSet<K, A> implements core.ops.BitOr<SortedSet<K, A>> {
    type Output = SortedSet<K, A>
    fn bitor(read rhs: SortedSet<K, A>): SortedSet<K, A> {
        var out = self.clone()
        for key in rhs.iter() { let _ = out.insert(K.(Clone).clone(key)) }
        out
    }
}
extend<K: Ord + Clone, A: Allocator + Clone> SortedSet<K, A> implements core.ops.BitAnd<SortedSet<K, A>> {
    type Output = SortedSet<K, A>
    fn bitand(read rhs: SortedSet<K, A>): SortedSet<K, A> {
        var out = set_new_in<K, A>(self.map.a.clone())
        for key in self.iter() {
            if rhs.contains(key) { let _ = out.insert(K.(Clone).clone(key)) }
        }
        out
    }
}
extend<K: Ord + Clone, A: Allocator + Clone> SortedSet<K, A> implements core.ops.Sub<SortedSet<K, A>> {
    type Output = SortedSet<K, A>
    fn sub(read rhs: SortedSet<K, A>): SortedSet<K, A> {
        var out = set_new_in<K, A>(self.map.a.clone())
        for key in self.iter() {
            if !rhs.contains(key) { let _ = out.insert(K.(Clone).clone(key)) }
        }
        out
    }
}
extend<K: Ord + Clone, A: Allocator + Clone> SortedSet<K, A> implements core.ops.BitXor<SortedSet<K, A>> {
    type Output = SortedSet<K, A>
    fn bitxor(read rhs: SortedSet<K, A>): SortedSet<K, A> {
        var out = set_new_in<K, A>(self.map.a.clone())
        for key in self.iter() {
            if !rhs.contains(key) { let _ = out.insert(K.(Clone).clone(key)) }
        }
        for key in rhs.iter() {
            if !self.contains(key) { let _ = out.insert(K.(Clone).clone(key)) }
        }
        out
    }
}

extend<region r, region s, K: Ord + Clone, A: Allocator + Clone>
    read SortedSet<K, A> from r implements core.ops.BitOr<read SortedSet<K, A> from s> {
    type Output = SortedSet<K, A>
    fn bitor(read rhs: read SortedSet<K, A> from s): SortedSet<K, A> {
        var out = set_new_in<K, A>(self.map.a.clone())
        for key in self.iter() { let _ = out.insert(K.(Clone).clone(key)) }
        for key in rhs.iter() { let _ = out.insert(K.(Clone).clone(key)) }
        out
    }
}
extend<region r, region s, K: Ord + Clone, A: Allocator + Clone>
    read SortedSet<K, A> from r implements core.ops.BitAnd<read SortedSet<K, A> from s> {
    type Output = SortedSet<K, A>
    fn bitand(read rhs: read SortedSet<K, A> from s): SortedSet<K, A> {
        var out = set_new_in<K, A>(self.map.a.clone())
        for key in self.iter() {
            if rhs.contains(key) { let _ = out.insert(K.(Clone).clone(key)) }
        }
        out
    }
}
extend<region r, region s, K: Ord + Clone, A: Allocator + Clone>
    read SortedSet<K, A> from r implements core.ops.Sub<read SortedSet<K, A> from s> {
    type Output = SortedSet<K, A>
    fn sub(read rhs: read SortedSet<K, A> from s): SortedSet<K, A> {
        var out = set_new_in<K, A>(self.map.a.clone())
        for key in self.iter() {
            if !rhs.contains(key) { let _ = out.insert(K.(Clone).clone(key)) }
        }
        out
    }
}
extend<region r, region s, K: Ord + Clone, A: Allocator + Clone>
    read SortedSet<K, A> from r implements core.ops.BitXor<read SortedSet<K, A> from s> {
    type Output = SortedSet<K, A>
    fn bitxor(read rhs: read SortedSet<K, A> from s): SortedSet<K, A> {
        var out = set_new_in<K, A>(self.map.a.clone())
        for key in self.iter() {
            if !rhs.contains(key) { let _ = out.insert(K.(Clone).clone(key)) }
        }
        for key in rhs.iter() {
            if !self.contains(key) { let _ = out.insert(K.(Clone).clone(key)) }
        }
        out
    }
}
