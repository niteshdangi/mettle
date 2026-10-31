import package.core.iter.{Iterator, BidirectionalIterator, ExactSizeIterator, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems}
import package.core.convert.From
import package.core.clone.Clone
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.hash.{Hash, Hasher}
import package.core.fmt

import super.alloc.{Allocator, Global, AllocError, PushError, layout_of, handle_alloc_error, panic_precondition}
import package.core.default.Default

type Node<T> {
    value: T
    prev: ptr<mut Node<T>>
    next: ptr<mut Node<T>>
}

// Doubly-linked list; every node is a separate block from the list's allocator.
pub type LinkedList<T, A: Allocator = Global> {
    head: ptr<mut Node<T>>
    tail: ptr<mut Node<T>>
    len: usize
    a: A
    drop {
        while self.len != 0usize {
            let v = self.pop_front()
        }
    }
}

pub fn new_in<T, A: Allocator>(a: take A): LinkedList<T, A> {
    LinkedList(core.ptr.null_mut<Node<T>>(), core.ptr.null_mut<Node<T>>(), 0usize, a)
}
pub fn new<T>(): LinkedList<T> { new_in(Global()) }

extend<T, A: Allocator> LinkedList<T, A> {
    pub fn len(): usize { self.len }
    pub fn is_empty(): bool { self.len == 0usize }

    mut fn alloc_node(value: take T, prev: ptr<mut Node<T>>, next: ptr<mut Node<T>>): ptr<mut Node<T>> throws AllocError {
        let raw = try self.a.allocate(layout_of<Node<T>>())
        let n = raw.cast<Node<T>>()
        unsafe { core.ptr.write(n, Node(value, prev, next)) }
        n
    }
    pub mut fn try_push_back(value: take T): Unit throws PushError<T> {
        let raw = match capture self.a.allocate(layout_of<Node<T>>()) {
            success(p) => p,
            failure(error) => { throw PushError(value, error) }
        }
        let n = raw.cast<Node<T>>()
        unsafe { core.ptr.write(n, Node(value, self.tail, core.ptr.null_mut<Node<T>>())) }
        if self.tail == core.ptr.null_mut<Node<T>>() { self.head = n } else { unsafe { (*self.tail).next = n } }
        self.tail = n
        self.len += 1usize
    }
    pub mut fn try_push_front(value: take T): Unit throws PushError<T> {
        let raw = match capture self.a.allocate(layout_of<Node<T>>()) {
            success(p) => p,
            failure(error) => { throw PushError(value, error) }
        }
        let n = raw.cast<Node<T>>()
        unsafe { core.ptr.write(n, Node(value, core.ptr.null_mut<Node<T>>(), self.head)) }
        if self.head == core.ptr.null_mut<Node<T>>() { self.tail = n } else { unsafe { (*self.head).prev = n } }
        self.head = n
        self.len += 1usize
    }
    pub mut fn push_back(value: take T): Unit {
        let n = match capture self.alloc_node(value, self.tail, core.ptr.null_mut<Node<T>>()) {
            success(n) => n,
            failure(_) => handle_alloc_error(layout_of<Node<T>>())
        }
        if self.tail == core.ptr.null_mut<Node<T>>() { self.head = n } else { unsafe { (*self.tail).next = n } }
        self.tail = n
        self.len += 1usize
    }
    pub mut fn push_front(value: take T): Unit {
        let n = match capture self.alloc_node(value, core.ptr.null_mut<Node<T>>(), self.head) {
            success(n) => n,
            failure(_) => handle_alloc_error(layout_of<Node<T>>())
        }
        if self.head == core.ptr.null_mut<Node<T>>() { self.tail = n } else { unsafe { (*self.head).prev = n } }
        self.head = n
        self.len += 1usize
    }
    pub mut fn pop_front(): T? {
        if self.len == 0usize { return none }
        let n = self.head
        let node = unsafe { core.ptr.`read`(n.cast_const()) }
        self.head = node.next
        if self.head == core.ptr.null_mut<Node<T>>() { self.tail = core.ptr.null_mut<Node<T>>() } else { unsafe { (*self.head).prev = core.ptr.null_mut<Node<T>>() } }
        self.len -= 1usize
        unsafe { self.a.deallocate(n.cast<u8>(), layout_of<Node<T>>()) }
        present(node.value)
    }
    pub mut fn pop_back(): T? {
        if self.len == 0usize { return none }
        let n = self.tail
        let node = unsafe { core.ptr.`read`(n.cast_const()) }
        self.tail = node.prev
        if self.tail == core.ptr.null_mut<Node<T>>() { self.head = core.ptr.null_mut<Node<T>>() } else { unsafe { (*self.tail).next = core.ptr.null_mut<Node<T>>() } }
        self.len -= 1usize
        unsafe { self.a.deallocate(n.cast<u8>(), layout_of<Node<T>>()) }
        present(node.value)
    }
    pub fn front(): (read T from self)? {
        if self.len == 0usize { return none }
        present(unsafe { read (*self.head).value })
    }
    pub fn back(): (read T from self)? {
        if self.len == 0usize { return none }
        present(unsafe { read (*self.tail).value })
    }
    pub mut fn front_mut(): (mut T from self)? {
        if self.len == 0usize { return none }
        present(unsafe { mut (*self.head).value })
    }
    pub mut fn back_mut(): (mut T from self)? {
        if self.len == 0usize { return none }
        present(unsafe { mut (*self.tail).value })
    }
    // Element at position `i`, walking from the nearer end.
    pub fn get(i: usize): (read T from self)? {
        if i >= self.len { return none }
        var p = self.head
        var k = 0usize
        while k < i {
            p = unsafe { (*p).next }
            k += 1usize
        }
        present(unsafe { read (*p).value })
    }
    pub mut fn get_mut(i: usize): (mut T from self)? {
        if i >= self.len { return none }
        var p = self.head
        var k = 0usize
        while k < i {
            p = unsafe { (*p).next }
            k += 1usize
        }
        present(unsafe { mut (*p).value })
    }
    pub mut fn clear(): Unit {
        while self.len != 0usize {
            let v = self.pop_front()
        }
    }
}

// Borrowed front-to-back iterator. `front` and `back` are the next nodes to
// yield from each end and `left` nodes remain, so the two ends never cross.
pub type ListIter<region r, T, A: Allocator> {
    list: read LinkedList<T, A> from r
    front: ptr<mut Node<T>>
    back: ptr<mut Node<T>>
    left: usize
}
extend<region r, T, A: Allocator> ListIter<region r, T, A> implements Iterator {
    type Item = read T from r
    mut fn next(): (read T from r)? {
        if self.left == 0usize { return none }
        let n = self.front
        self.left -= 1usize
        self.front = unsafe { (*n).next }
        present(unsafe { read (*n).value })
    }
    fn size_hint(): (usize, usize?) { (self.left, present(self.left)) }
}
extend<region r, T, A: Allocator> ListIter<region r, T, A> implements BidirectionalIterator {
    mut fn next_back(): (read T from r)? {
        if self.left == 0usize { return none }
        let n = self.back
        self.left -= 1usize
        self.back = unsafe { (*n).prev }
        present(unsafe { read (*n).value })
    }
}
extend<region r, T, A: Allocator> ListIter<region r, T, A> implements ExactSizeIterator {
    fn len(): usize { self.left }
}
extend<T, A: Allocator> LinkedList<T, A> implements Iterable {
    type Item = T
    type Iter<region r> = ListIter<region r, T, A>
    fn iter<region r>(receiver self: read Self from r): ListIter<region r, T, A> {
        ListIter(read self, self.head, self.tail, self.len)
    }
}

// Mutable front-to-back iterator with the same front/back/left protocol.
pub type ListIterMut<region r, T, A: Allocator> {
    list: mut LinkedList<T, A> from r
    front: ptr<mut Node<T>>
    back: ptr<mut Node<T>>
    left: usize
}
extend<region r, T, A: Allocator> ListIterMut<region r, T, A> implements Iterator {
    type Item = mut T from r
    mut fn next(): (mut T from r)? {
        if self.left == 0usize { return none }
        let n = self.front
        self.left -= 1usize
        self.front = unsafe { (*n).next }
        present(unsafe { mut (*n).value })
    }
    fn size_hint(): (usize, usize?) { (self.left, present(self.left)) }
}
extend<region r, T, A: Allocator> ListIterMut<region r, T, A> implements BidirectionalIterator {
    mut fn next_back(): (mut T from r)? {
        if self.left == 0usize { return none }
        let n = self.back
        self.left -= 1usize
        self.back = unsafe { (*n).prev }
        present(unsafe { mut (*n).value })
    }
}
extend<region r, T, A: Allocator> ListIterMut<region r, T, A> implements ExactSizeIterator {
    fn len(): usize { self.left }
}
extend<T, A: Allocator> LinkedList<T, A> implements MutableIterable {
    type Item = T
    type IterMut<region r> = ListIterMut<region r, T, A>
    fn iter_mut<region r>(receiver self: mut Self from r): ListIterMut<region r, T, A> {
        let first = self.head
        let last = self.tail
        let count = self.len
        ListIterMut(mut self, first, last, count)
    }
}

pub type LinkedListIntoIter<T, A: Allocator = Global> { list: LinkedList<T, A> }
extend<T, A: Allocator> LinkedListIntoIter<T, A> implements Iterator {
    type Item = T
    mut fn next(): T? { self.list.pop_front() }
    fn size_hint(): (usize, usize?) { (self.list.len, present(self.list.len)) }
}
extend<T, A: Allocator> LinkedListIntoIter<T, A> implements BidirectionalIterator {
    mut fn next_back(): T? { self.list.pop_back() }
}
extend<T, A: Allocator> LinkedListIntoIter<T, A> implements ExactSizeIterator {
    fn len(): usize { self.list.len }
}
extend<T, A: Allocator> LinkedList<T, A> implements OwnedIterable {
    type Item = T
    type IntoIter = LinkedListIntoIter<T, A>
    fn into_iter(receiver self: take Self): LinkedListIntoIter<T, A> {
        LinkedListIntoIter(take self)
    }
}

extend<T: Clone, A: Allocator + Clone> LinkedList<T, A> implements Clone {
    fn clone(): LinkedList<T, A> {
        var out = new_in<T, A>(self.a.clone())
        var p = self.head
        while p != core.ptr.null_mut<Node<T>>() {
            out.push_back(unsafe { read (*p).value }.clone())
            p = unsafe { (*p).next }
        }
        out
    }
}
extend<T: PartialEq, A: Allocator> LinkedList<T, A> implements PartialEq {
    fn eq(other: read LinkedList<T, A>): bool {
        if self.len != other.len { return false }
        var p = self.head
        var q = other.head
        while p != core.ptr.null_mut<Node<T>>() {
            if !unsafe { read (*p).value }.eq(unsafe { read (*q).value }) { return false }
            p = unsafe { (*p).next }
            q = unsafe { (*q).next }
        }
        true
    }
}
extend<T: Eq, A: Allocator> LinkedList<T, A> implements Eq {}
extend<T: PartialOrd, A: Allocator> LinkedList<T, A> implements PartialOrd {
    fn partial_cmp(other: read LinkedList<T, A>): Ordering? {
        var p = self.head
        var q = other.head
        while p != core.ptr.null_mut<Node<T>>() && q != core.ptr.null_mut<Node<T>>() {
            match unsafe { read (*p).value }.partial_cmp(unsafe { read (*q).value }) {
                present(o) => { if !o.is_eq() { return present(o) } },
                none => { return none }
            }
            p = unsafe { (*p).next }
            q = unsafe { (*q).next }
        }
        self.len.partial_cmp(other.len)
    }
}
extend<T: Ord, A: Allocator> LinkedList<T, A> implements Ord {
    fn cmp(other: read LinkedList<T, A>): Ordering {
        var p = self.head
        var q = other.head
        while p != core.ptr.null_mut<Node<T>>() && q != core.ptr.null_mut<Node<T>>() {
            let o = unsafe { read (*p).value }.cmp(unsafe { read (*q).value })
            if !o.is_eq() { return o }
            p = unsafe { (*p).next }
            q = unsafe { (*q).next }
        }
        self.len.cmp(other.len)
    }
}
extend<T: Hash, A: Allocator> LinkedList<T, A> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit {
        state.write_usize(self.len)
        var p = self.head
        while p != core.ptr.null_mut<Node<T>>() {
            unsafe { read (*p).value }.hash(mut state)
            p = unsafe { (*p).next }
        }
    }
}
extend<T: fmt.Debug, A: Allocator> LinkedList<T, A> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try f.debug_open("[")
        var p = self.head
        var first = true
        while p != core.ptr.null_mut<Node<T>>() {
            try f.debug_item_start(first)
            try T.(fmt.Debug).fmt(unsafe { read (*p).value }, mut f)
            try f.debug_item_end()
            first = false
            p = unsafe { (*p).next }
        }
        try f.debug_close("]", self.len == 0usize)
    }
}
extend<T, A: Allocator> LinkedList<T, A> implements ExtendItems<T> {
    mut fn extend<I: OwnedIterable<Item = T>>(items: take I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { self.push_back(item) }, none => { break } }
        }
    }
}
extend<T> LinkedList<T> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(items: take I): LinkedList<T> {
        var out = new<T>()
        out.extend(items)
        out
    }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<T: Transferable, A: Allocator + Transferable> LinkedList<T, A> implements Transferable {}
unsafe extend<T: Shareable, A: Allocator + Shareable> LinkedList<T, A> implements Shareable {}

extend<T, const N: usize> LinkedList<T> implements From<[T; N]> {
    static fn `from`(value: take [T; N]): LinkedList<T> {
        var out = new<T>()
        out.extend(super.vec.from_array(value))
        out
    }
}

extend<T, A: Allocator + Default> LinkedList<T, A> implements Default {
    static fn default(): LinkedList<T, A> { new_in(A.(Default).default()) }
}

extend<T, A: Allocator> LinkedList<T, A> {
    // Detaches `n` and returns its value. `n` must be a live node of this list.
    mut fn unlink(n: ptr<mut Node<T>>): T {
        let node = unsafe { core.ptr.`read`(n.cast_const()) }
        if node.prev == core.ptr.null_mut<Node<T>>() { self.head = node.next } else { unsafe { (*node.prev).next = node.next } }
        if node.next == core.ptr.null_mut<Node<T>>() { self.tail = node.prev } else { unsafe { (*node.next).prev = node.prev } }
        self.len -= 1usize
        unsafe { self.a.deallocate(n.cast<u8>(), layout_of<Node<T>>()) }
        node.value
    }
    // Links a new node between adjacent nodes `prev` and `next` (either may be null).
    mut fn link_between(prev: ptr<mut Node<T>>, next: ptr<mut Node<T>>, value: take T): ptr<mut Node<T>> {
        let n = match capture self.alloc_node(value, prev, next) {
            success(n) => n,
            failure(_) => handle_alloc_error(layout_of<Node<T>>())
        }
        if prev == core.ptr.null_mut<Node<T>>() { self.head = n } else { unsafe { (*prev).next = n } }
        if next == core.ptr.null_mut<Node<T>>() { self.tail = n } else { unsafe { (*next).prev = n } }
        self.len += 1usize
        n
    }
    fn node_at(i: usize): ptr<mut Node<T>> {
        var p = self.head
        var k = 0usize
        while k < i {
            p = unsafe { (*p).next }
            k += 1usize
        }
        p
    }

    // Moves every node of `other` to the back of this list. `other` is left empty.
    pub mut fn append(other: mut LinkedList<T, A>): Unit {
        if other.len == 0usize { return () }
        if self.len == 0usize {
            self.head = other.head
        } else {
            unsafe { (*self.tail).next = other.head }
            unsafe { (*other.head).prev = self.tail }
        }
        self.tail = other.tail
        self.len += other.len
        other.head = core.ptr.null_mut<Node<T>>()
        other.tail = core.ptr.null_mut<Node<T>>()
        other.len = 0usize
    }
    // Returns the elements from `at` to the back; `at > len` is a precondition failure.
    pub mut fn split_off(at: usize): LinkedList<T, A> where A: Clone {
        if at > self.len { panic_precondition() }
        var out = new_in<T, A>(self.a.clone())
        if at == self.len { return out }
        if at == 0usize {
            out.head = self.head
            out.tail = self.tail
            out.len = self.len
            self.head = core.ptr.null_mut<Node<T>>()
            self.tail = core.ptr.null_mut<Node<T>>()
            self.len = 0usize
            return out
        }
        let n = self.node_at(at)
        let before = unsafe { (*n).prev }
        unsafe { (*before).next = core.ptr.null_mut<Node<T>>() }
        unsafe { (*n).prev = core.ptr.null_mut<Node<T>>() }
        out.head = n
        out.tail = self.tail
        out.len = self.len - at
        self.tail = before
        self.len = at
        out
    }
    // Removes the element at `at`; `at >= len` is a precondition failure.
    pub mut fn remove(at: usize): T {
        if at >= self.len { panic_precondition() }
        let n = self.node_at(at)
        self.unlink(n)
    }
    // Keeps the elements accepted by `keep`, in order. The list stays valid if `keep` panics.
    pub mut fn retain<F: mut fn(read T): bool>(keep: mut F): Unit {
        var p = self.head
        while p != core.ptr.null_mut<Node<T>>() {
            let next = unsafe { (*p).next }
            if !keep(unsafe { read (*p).value }) {
                let removed = self.unlink(p)
            }
            p = next
        }
    }
    pub mut fn retain_mut<F: mut fn(mut T): bool>(keep: mut F): Unit {
        var p = self.head
        while p != core.ptr.null_mut<Node<T>>() {
            let next = unsafe { (*p).next }
            if !keep(unsafe { mut (*p).value }) {
                let removed = self.unlink(p)
            }
            p = next
        }
    }
    pub mut fn extract_if<F: mut fn(mut T): bool>(test: take F): ListExtractIf<region self, T, A, F> {
        let first = self.head
        ListExtractIf(mut self, first, test)
    }
}

extend<T: PartialEq, A: Allocator> LinkedList<T, A> {
    pub fn contains(value: read T): bool {
        var p = self.head
        while p != core.ptr.null_mut<Node<T>>() {
            if unsafe { read (*p).value }.eq(value) { return true }
            p = unsafe { (*p).next }
        }
        false
    }
}

// Lazily removes, front to back, the elements accepted by the predicate;
// elements not yet visited stay in the list if the iterator is dropped early.
pub type ListExtractIf<region r, T, A: Allocator, F> {
    list: mut LinkedList<T, A> from r
    node: ptr<mut Node<T>>
    predicate: F
}
extend<region r, T, A: Allocator, F: mut fn(mut T): bool> ListExtractIf<region r, T, A, F> implements Iterator {
    type Item = T
    mut fn next(): T? {
        while self.node != core.ptr.null_mut<Node<T>>() {
            let n = self.node
            self.node = unsafe { (*n).next }
            if self.predicate(unsafe { mut (*n).value }) {
                return present(self.list.unlink(n))
            }
        }
        none
    }
}

// Read-only cursor. A null `node` is the ghost position between back and front,
// whose index is `len`.
pub type Cursor<region r, T, A: Allocator> {
    list: read LinkedList<T, A> from r
    node: ptr<mut Node<T>>
    position: usize
}
extend<region r, T, A: Allocator> Cursor<region r, T, A> {
    pub fn index(): usize? {
        if self.node == core.ptr.null_mut<Node<T>>() { none } else { present(self.position) }
    }
    pub fn current(): (read T from r)? {
        if self.node == core.ptr.null_mut<Node<T>>() { return none }
        present(unsafe { read (*self.node).value })
    }
    pub mut fn move_next(): Unit {
        if self.node == core.ptr.null_mut<Node<T>>() {
            self.node = self.list.head
            self.position = 0usize
        } else {
            self.node = unsafe { (*self.node).next }
            if self.node == core.ptr.null_mut<Node<T>>() { self.position = self.list.len } else { self.position += 1usize }
        }
    }
    pub mut fn move_prev(): Unit {
        if self.node == core.ptr.null_mut<Node<T>>() {
            self.node = self.list.tail
            if self.node != core.ptr.null_mut<Node<T>>() { self.position = self.list.len - 1usize }
        } else {
            self.node = unsafe { (*self.node).prev }
            if self.node == core.ptr.null_mut<Node<T>>() { self.position = self.list.len } else { self.position -= 1usize }
        }
    }
    pub fn peek_next(): (read T from r)? {
        let n = if self.node == core.ptr.null_mut<Node<T>>() { self.list.head } else { unsafe { (*self.node).next } }
        if n == core.ptr.null_mut<Node<T>>() { return none }
        present(unsafe { read (*n).value })
    }
    pub fn peek_prev(): (read T from r)? {
        let n = if self.node == core.ptr.null_mut<Node<T>>() { self.list.tail } else { unsafe { (*self.node).prev } }
        if n == core.ptr.null_mut<Node<T>>() { return none }
        present(unsafe { read (*n).value })
    }
}

// Mutable cursor that can also insert and remove at its position.
pub type CursorMut<region r, T, A: Allocator> {
    list: mut LinkedList<T, A> from r
    node: ptr<mut Node<T>>
    position: usize
}
extend<region r, T, A: Allocator> CursorMut<region r, T, A> {
    pub fn index(): usize? {
        if self.node == core.ptr.null_mut<Node<T>>() { none } else { present(self.position) }
    }
    pub mut fn current(): (mut T from self)? {
        if self.node == core.ptr.null_mut<Node<T>>() { return none }
        present(unsafe { mut (*self.node).value })
    }
    pub mut fn move_next(): Unit {
        if self.node == core.ptr.null_mut<Node<T>>() {
            self.node = self.list.head
            self.position = 0usize
        } else {
            self.node = unsafe { (*self.node).next }
            if self.node == core.ptr.null_mut<Node<T>>() { self.position = self.list.len } else { self.position += 1usize }
        }
    }
    pub mut fn move_prev(): Unit {
        if self.node == core.ptr.null_mut<Node<T>>() {
            self.node = self.list.tail
            if self.node != core.ptr.null_mut<Node<T>>() { self.position = self.list.len - 1usize }
        } else {
            self.node = unsafe { (*self.node).prev }
            if self.node == core.ptr.null_mut<Node<T>>() { self.position = self.list.len } else { self.position -= 1usize }
        }
    }
    pub mut fn peek_next(): (mut T from self)? {
        let n = if self.node == core.ptr.null_mut<Node<T>>() { self.list.head } else { unsafe { (*self.node).next } }
        if n == core.ptr.null_mut<Node<T>>() { return none }
        present(unsafe { mut (*n).value })
    }
    pub mut fn peek_prev(): (mut T from self)? {
        let n = if self.node == core.ptr.null_mut<Node<T>>() { self.list.tail } else { unsafe { (*self.node).prev } }
        if n == core.ptr.null_mut<Node<T>>() { return none }
        present(unsafe { mut (*n).value })
    }
    // Inserts after the current element; at the ghost position this inserts at the front.
    pub mut fn insert_after(value: take T): Unit {
        let prev = self.node
        let next = if prev == core.ptr.null_mut<Node<T>>() { self.list.head } else { unsafe { (*prev).next } }
        let created = self.list.link_between(prev, next, value)
        if prev == core.ptr.null_mut<Node<T>>() { self.position = self.list.len }
    }
    // Inserts before the current element; at the ghost position this inserts at the back.
    // The cursor keeps pointing at the same element, whose index grows by one.
    pub mut fn insert_before(value: take T): Unit {
        let next = self.node
        let prev = if next == core.ptr.null_mut<Node<T>>() { self.list.tail } else { unsafe { (*next).prev } }
        let created = self.list.link_between(prev, next, value)
        if next == core.ptr.null_mut<Node<T>>() { self.position = self.list.len } else { self.position += 1usize }
    }
    // Removes the current element and moves to the one after it (the ghost if it was last).
    pub mut fn remove_current(): T? {
        if self.node == core.ptr.null_mut<Node<T>>() { return none }
        let n = self.node
        self.node = unsafe { (*n).next }
        let value = self.list.unlink(n)
        if self.node == core.ptr.null_mut<Node<T>>() { self.position = self.list.len }
        present(value)
    }
}

extend<T, A: Allocator> LinkedList<T, A> {
    pub fn cursor_front(): Cursor<region self, T, A> { Cursor(read self, self.head, 0usize) }
    pub fn cursor_back(): Cursor<region self, T, A> {
        let last = self.tail
        let at = if self.len == 0usize { 0usize } else { self.len - 1usize }
        Cursor(read self, last, at)
    }
    pub mut fn cursor_front_mut(): CursorMut<region self, T, A> {
        let first = self.head
        CursorMut(mut self, first, 0usize)
    }
    pub mut fn cursor_back_mut(): CursorMut<region self, T, A> {
        let last = self.tail
        let at = if self.len == 0usize { 0usize } else { self.len - 1usize }
        CursorMut(mut self, last, at)
    }
}
