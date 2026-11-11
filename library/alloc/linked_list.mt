import package.core.iter.{Iterator, BidirectionalIterator, ExactSizeIterator, FusedIterator, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems}
import package.core.clone.Clone
import package.core.default.Default
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.hash.{Hash, Hasher}
import package.core.fmt

import super.alloc.{Allocator, Global, AllocError, PushError, layout_of, handle_alloc_error}

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
        var remaining = LinkedDrop(core.ptr.from_mut(self))
        remaining.run()
    }
}

// Safety: list is exclusive and live; pop_front unlinks each owner before allocator/destructor callbacks.
type LinkedDrop<T, A: Allocator> {
    list: ptr<mut LinkedList<T, A>>
    drop { self.run() }
}

extend<T, A: Allocator> LinkedDrop<T, A> {
    mut fn run(): Unit {
        while unsafe { (*self.list).len } != 0usize {
            let value = unsafe { (*self.list).pop_front() }
        }
    }
}

pub fn new_in<T, A: Allocator>(take a: A): LinkedList<T, A> {
    LinkedList(core.ptr.null_mut<Node<T>>(), core.ptr.null_mut<Node<T>>(), 0usize, a)
}
pub fn new<T>(): LinkedList<T> { new_in(Global()) }

extend<T, A: Allocator + Default> LinkedList<T, A> implements Default {
    static fn default(): LinkedList<T, A> { new_in(A.(Default).default()) }
}

extend<T, A: Allocator> LinkedList<T, A> {
    pub fn len(): usize { self.len }
    pub fn is_empty(): bool { self.len == 0usize }

    mut fn alloc_node(take value: T, prev: ptr<mut Node<T>>, next: ptr<mut Node<T>>): ptr<mut Node<T>> throws AllocError {
        let raw = try self.a.allocate(layout_of<Node<T>>())
        let n = raw.cast<Node<T>>()
        unsafe { core.ptr.write(n, Node(value, prev, next)) }
        n
    }
    pub mut fn try_push_back(take value: T): Unit throws PushError<T> {
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
    pub mut fn try_push_front(take value: T): Unit throws PushError<T> {
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
    pub mut fn push_back(take value: T): Unit {
        let n = match capture self.alloc_node(value, self.tail, core.ptr.null_mut<Node<T>>()) {
            success(n) => n,
            failure(_) => handle_alloc_error(layout_of<Node<T>>())
        }
        if self.tail == core.ptr.null_mut<Node<T>>() { self.head = n } else { unsafe { (*self.tail).next = n } }
        self.tail = n
        self.len += 1usize
    }
    pub mut fn push_back_mut(take value: T): mut T from self {
        self.push_back(value)
        unsafe { mut (*self.tail).value }
    }
    pub mut fn push_front(take value: T): Unit {
        let n = match capture self.alloc_node(value, core.ptr.null_mut<Node<T>>(), self.head) {
            success(n) => n,
            failure(_) => handle_alloc_error(layout_of<Node<T>>())
        }
        if self.head == core.ptr.null_mut<Node<T>>() { self.tail = n } else { unsafe { (*self.head).prev = n } }
        self.head = n
        self.len += 1usize
    }
    pub mut fn push_front_mut(take value: T): mut T from self {
        self.push_front(value)
        unsafe { mut (*self.head).value }
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

    pub mut fn extract_if<F: mut fn(mut T): bool>(
        take test: F
    ): LinkedListExtractIf<region self, T, A, F> {
        let first = self.head
        let remaining = self.len
        LinkedListExtractIf(
            mut self,
            first,
            core.ptr.null_mut<Node<T>>(),
            remaining,
            test
        )
    }
}

extend<T: PartialEq, A: Allocator> LinkedList<T, A> {
    pub fn contains(read value: T): bool {
        var node = self.head
        let null = core.ptr.null_mut<Node<T>>()
        while node != null {
            if unsafe { read (*node).value }.eq(value) { return true }
            node = unsafe { (*node).next }
        }
        false
    }
}

extend<T, A: Allocator + Clone> LinkedList<T, A> {
    // Rebuild nodes with the cloned allocator instead of transferring blocks
    // whose compatibility with that clone is not part of Allocator's contract.
    pub mut fn split_off(at: usize): LinkedList<T, A> {
        if at > self.len { super.alloc.panic_precondition() }
        var other = new_in<T, A>(self.a.clone())
        while self.len > at {
            other.push_front(self.pop_back().unwrap())
        }
        other
    }
}

// Global lists can splice nodes directly; custom allocators need an explicit
// compatibility contract before their independently owned node blocks can mix.
extend<T> LinkedList<T> {
    pub mut fn append(mut other: LinkedList<T>): Unit {
        let total = match self.len.checked_add(other.len) {
            present(n) => n,
            none => super.alloc.panic_precondition()
        }
        if other.len == 0usize { return () }
        let null = core.ptr.null_mut<Node<T>>()
        if self.tail == null {
            self.head = other.head
        } else {
            unsafe {
                (*self.tail).next = other.head
                (*other.head).prev = self.tail
            }
        }
        self.tail = other.tail
        self.len = total
        other.head = null
        other.tail = null
        other.len = 0usize
    }
}

pub type LinkedListExtractIf<region r, T, A: Allocator, F> {
    list: mut LinkedList<T, A> from r
    current: ptr<mut Node<T>>
    previous: ptr<mut Node<T>>
    remaining: usize
    test: F
}
extend<region r, T, A: Allocator, F: mut fn(mut T): bool> LinkedListExtractIf<region r, T, A, F> implements Iterator {
    type Item = T
    fn size_hint(): (usize, usize?) { (0usize, present(self.remaining)) }
    mut fn next(): T? {
        let null = core.ptr.null_mut<Node<T>>()
        while self.current != null {
            let current = self.current
            let next = unsafe { (*current).next }
            let remove = self.test(unsafe { mut (*current).value })
            self.remaining -= 1usize
            if remove {
                if self.previous == null {
                    self.list.head = next
                } else {
                    unsafe { (*self.previous).next = next }
                }
                if next == null {
                    self.list.tail = self.previous
                } else {
                    unsafe { (*next).prev = self.previous }
                }
                self.list.len -= 1usize
                self.current = next

                let node = unsafe { core.ptr.`read`(current.cast_const()) }
                unsafe { self.list.a.deallocate(current.cast<u8>(), layout_of<Node<T>>()) }
                return present(node.value)
            }
            self.previous = current
            self.current = next
        }
        none
    }
}
extend<region r, T, A: Allocator, F: mut fn(mut T): bool> LinkedListExtractIf<region r, T, A, F> implements FusedIterator {}

// Borrowed iterators keep both ends and the remaining node count.
pub type ListIter<region r, T, A: Allocator> {
    list: read LinkedList<T, A> from r
    front: ptr<mut Node<T>>
    back: ptr<mut Node<T>>
    remaining: usize
}
extend<region r, T, A: Allocator> ListIter<region r, T, A> implements Iterator {
    type Item = read T from r
    fn size_hint(): (usize, usize?) { (self.remaining, present(self.remaining)) }
    mut fn next(): (read T from r)? {
        if self.remaining == 0usize { return none }
        let n = self.front
        self.front = unsafe { (*n).next }
        self.remaining -= 1usize
        present(unsafe { read (*n).value })
    }
}
extend<region r, T, A: Allocator> ListIter<region r, T, A> implements BidirectionalIterator {
    mut fn next_back(): (read T from r)? {
        if self.remaining == 0usize { return none }
        let n = self.back
        self.back = unsafe { (*n).prev }
        self.remaining -= 1usize
        present(unsafe { read (*n).value })
    }
}
extend<region r, T, A: Allocator> ListIter<region r, T, A> implements ExactSizeIterator {}
extend<region r, T, A: Allocator> ListIter<region r, T, A> implements FusedIterator {}
extend<T, A: Allocator> LinkedList<T, A> implements Iterable {
    type Item = T
    type Iter<region r> = ListIter<region r, T, A>
    fn iter<region r>(receiver read self: Self from r): ListIter<region r, T, A> {
        ListIter(read self, self.head, self.tail, self.len)
    }
}

// The remaining count prevents mixed-end traversal from yielding a node twice.
pub type ListIterMut<region r, T, A: Allocator> {
    list: mut LinkedList<T, A> from r
    front: ptr<mut Node<T>>
    back: ptr<mut Node<T>>
    remaining: usize
}
extend<region r, T, A: Allocator> ListIterMut<region r, T, A> implements Iterator {
    type Item = mut T from r
    fn size_hint(): (usize, usize?) { (self.remaining, present(self.remaining)) }
    mut fn next(): (mut T from r)? {
        if self.remaining == 0usize { return none }
        let n = self.front
        self.front = unsafe { (*n).next }
        self.remaining -= 1usize
        present(unsafe { mut (*n).value })
    }
}
extend<region r, T, A: Allocator> ListIterMut<region r, T, A> implements BidirectionalIterator {
    mut fn next_back(): (mut T from r)? {
        if self.remaining == 0usize { return none }
        let n = self.back
        self.back = unsafe { (*n).prev }
        self.remaining -= 1usize
        present(unsafe { mut (*n).value })
    }
}
extend<region r, T, A: Allocator> ListIterMut<region r, T, A> implements ExactSizeIterator {}
extend<region r, T, A: Allocator> ListIterMut<region r, T, A> implements FusedIterator {}
extend<T, A: Allocator> LinkedList<T, A> implements MutableIterable {
    type Item = T
    type IterMut<region r> = ListIterMut<region r, T, A>
    fn iter_mut<region r>(receiver mut self: Self from r): ListIterMut<region r, T, A> {
        let front = self.head
        let back = self.tail
        let remaining = self.len
        ListIterMut(mut self, front, back, remaining)
    }
}

pub type LinkedListIntoIter<T, A: Allocator = Global> { list: LinkedList<T, A> }
extend<T, A: Allocator> LinkedListIntoIter<T, A> implements Iterator {
    type Item = T
    fn size_hint(): (usize, usize?) {
        let remaining = self.list.len
        (remaining, present(remaining))
    }
    mut fn next(): T? { self.list.pop_front() }
}
extend<T, A: Allocator> LinkedListIntoIter<T, A> implements BidirectionalIterator {
    mut fn next_back(): T? { self.list.pop_back() }
}
extend<T, A: Allocator> LinkedListIntoIter<T, A> implements ExactSizeIterator {}
extend<T, A: Allocator> LinkedListIntoIter<T, A> implements FusedIterator {}
extend<T, A: Allocator> LinkedList<T, A> implements OwnedIterable {
    type Item = T
    type IntoIter = LinkedListIntoIter<T, A>
    fn into_iter(receiver take self: Self): LinkedListIntoIter<T, A> {
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
    fn eq(read other: LinkedList<T, A>): bool {
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
    fn partial_cmp(read other: LinkedList<T, A>): Ordering? {
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
    fn cmp(read other: LinkedList<T, A>): Ordering {
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
    fn hash<H: Hasher>(mut state: H): Unit {
        state.write_usize(self.len)
        var p = self.head
        while p != core.ptr.null_mut<Node<T>>() {
            unsafe { read (*p).value }.hash(mut state)
            p = unsafe { (*p).next }
        }
    }
}
extend<T: fmt.Debug, A: Allocator> LinkedList<T, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
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
    mut fn extend<I: OwnedIterable<Item = T>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { self.push_back(item) }, none => { break } }
        }
    }
}
extend<T> LinkedList<T> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(take items: I): LinkedList<T> {
        var out = new<T>()
        out.extend(items)
        out
    }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<T: Transferable, A: Allocator + Transferable> LinkedList<T, A> implements Transferable {}
unsafe extend<T: Shareable, A: Allocator + Shareable> LinkedList<T, A> implements Shareable {}
