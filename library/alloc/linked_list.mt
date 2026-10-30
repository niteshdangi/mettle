import package.core.iter.{Iterator, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems};
import package.core.clone.Clone;
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd};
import package.core.hash.{Hash, Hasher};
import package.core.fmt;

import super.alloc.{Allocator, Global, AllocError, layout_of, handle_alloc_error};

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
    pub mut fn try_push_back(value: take T): Unit throws AllocError {
        let n = try self.alloc_node(value, self.tail, core.ptr.null_mut<Node<T>>())
        if self.tail == core.ptr.null_mut<Node<T>>() { self.head = n } else { unsafe { (*self.tail).next = n } }
        self.tail = n
        self.len += 1usize
    }
    pub mut fn try_push_front(value: take T): Unit throws AllocError {
        let n = try self.alloc_node(value, core.ptr.null_mut<Node<T>>(), self.head)
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
    pub mut fn clear(): Unit {
        while self.len != 0usize {
            let v = self.pop_front()
        }
    }
}

// Borrowed front-to-back iterator; `node` is null once the list is exhausted.
pub type ListIter<region r, T, A: Allocator> { list: read LinkedList<T, A> from r; node: ptr<mut Node<T>> }
extend<region r, T, A: Allocator> ListIter<region r, T, A> implements Iterator {
    type Item = read T from r
    mut fn next(): (read T from r)? {
        if self.node == core.ptr.null_mut<Node<T>>() { return none }
        let n = self.node
        self.node = unsafe { (*n).next }
        present(unsafe { read (*n).value })
    }
}
extend<T, A: Allocator> LinkedList<T, A> implements Iterable {
    type Item = T
    type Iter<region r> = ListIter<region r, T, A>
    fn iter<region r>(receiver self: read Self from r): ListIter<region r, T, A> { ListIter(read self, self.head) }
}

// Mutable front-to-back iterator; `node` is null once the list is exhausted.
pub type ListIterMut<region r, T, A: Allocator> { list: mut LinkedList<T, A> from r; node: ptr<mut Node<T>> }
extend<region r, T, A: Allocator> ListIterMut<region r, T, A> implements Iterator {
    type Item = mut T from r
    mut fn next(): (mut T from r)? {
        if self.node == core.ptr.null_mut<Node<T>>() { return none }
        let n = self.node
        self.node = unsafe { (*n).next }
        present(unsafe { mut (*n).value })
    }
}
extend<T, A: Allocator> LinkedList<T, A> implements MutableIterable {
    type Item = T
    type IterMut<region r> = ListIterMut<region r, T, A>
    fn iter_mut<region r>(receiver self: mut Self from r): ListIterMut<region r, T, A> {
        let first = self.head
        ListIterMut(mut self, first)
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
    fn fmt<W: fmt.Write>(f: mut fmt.Formatter<W>): Unit throws fmt.Error {
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
