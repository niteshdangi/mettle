import package.core.iter.{Iterator, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems};
import package.core.clone.Clone;
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd};
import package.core.hash.{Hash, Hasher};
import package.core.fmt;

import super.alloc.{Allocator, Global, AllocError, layout_unchecked, handle_alloc_error, layout_of, dangling_for};

// Growable ring buffer owning its block and allocator.
pub type Deque<T, A: Allocator = Global> {
    buf: ptr<mut T>
    cap: usize
    head: usize
    len: usize
    a: A
    drop {
        while self.len != 0usize {
            let v = self.pop_front()
        }
        if self.cap != 0usize && core.mem.size_of<T>() != 0usize {
            let layout = unsafe { layout_unchecked(self.cap * core.mem.size_of<T>(), core.mem.align_of<T>()) }
            unsafe { self.a.deallocate(self.buf.cast<u8>(), layout) }
        }
    }
}

pub fn new_in<T, A: Allocator>(a: take A): Deque<T, A> {
    let cap = if core.mem.size_of<T>() == 0usize { 0x7fffffffffffffffusize } else { 0usize }
    Deque(dangling_for<T>(), cap, 0usize, 0usize, a)
}
pub fn new<T>(): Deque<T> { new_in(Global()) }

extend<T, A: Allocator> Deque<T, A> {
    pub fn len(): usize { self.len }
    pub fn capacity(): usize { self.cap }
    pub fn is_empty(): bool { self.len == 0usize }
    pub fn allocator(): read A from self { read self.a }

    fn physical(i: usize): usize {
        let j = self.head + i
        if j >= self.cap { j - self.cap } else { j }
    }

    // Moves the elements to the front of a larger block; failure changes nothing.
    mut fn grow(): Unit throws AllocError {
        let size = core.mem.size_of<T>()
        if size == 0usize { return () }
        let ncap = if self.cap == 0usize { 4usize } else { self.cap * 2usize }
        let align = core.mem.align_of<T>()
        let bytes = match ncap.checked_mul(size) {
            present(b) => b,
            none => throw AllocError(0xffffffffffffffffusize, align)
        }
        let np = (try self.a.allocate(unsafe { layout_unchecked(bytes, align) })).cast<T>()
        var i = 0usize
        while i < self.len {
            unsafe { core.ptr.`copy`(self.buf.add(self.physical(i)).cast_const(), np.add(i), 1usize) }
            i += 1usize
        }
        if self.cap != 0usize {
            unsafe { self.a.deallocate(self.buf.cast<u8>(), layout_unchecked(self.cap * size, align)) }
        }
        self.buf = np
        self.cap = ncap
        self.head = 0usize
    }
    pub mut fn try_reserve_one(): Unit throws AllocError {
        if self.len == self.cap { try self.grow() }
    }
    pub mut fn try_push_back(value: take T): Unit throws AllocError {
        try self.try_reserve_one()
        let at = self.physical(self.len)
        unsafe { core.ptr.write(self.buf.add(at), value) }
        self.len += 1usize
    }
    pub mut fn try_push_front(value: take T): Unit throws AllocError {
        try self.try_reserve_one()
        self.head = if self.head == 0usize { self.cap - 1usize } else { self.head - 1usize }
        unsafe { core.ptr.write(self.buf.add(self.head), value) }
        self.len += 1usize
    }
    pub mut fn push_back(value: take T): Unit {
        match capture self.try_reserve_one() {
            success(_) => {},
            failure(_) => handle_alloc_error(layout_of<T>())
        }
        let at = self.physical(self.len)
        unsafe { core.ptr.write(self.buf.add(at), value) }
        self.len += 1usize
    }
    pub mut fn push_front(value: take T): Unit {
        match capture self.try_reserve_one() {
            success(_) => {},
            failure(_) => handle_alloc_error(layout_of<T>())
        }
        self.head = if self.head == 0usize { self.cap - 1usize } else { self.head - 1usize }
        unsafe { core.ptr.write(self.buf.add(self.head), value) }
        self.len += 1usize
    }
    pub mut fn pop_front(): T? {
        if self.len == 0usize { return none }
        let v = unsafe { core.ptr.`read`(self.buf.add(self.head)) }
        self.head = self.physical(1usize)
        self.len -= 1usize
        present(v)
    }
    pub mut fn pop_back(): T? {
        if self.len == 0usize { return none }
        self.len -= 1usize
        present(unsafe { core.ptr.`read`(self.buf.add(self.physical(self.len))) })
    }
    pub fn get(i: usize): (read T from self)? {
        if i >= self.len { return none }
        present(unsafe { read *self.buf.add(self.physical(i)) })
    }
    pub mut fn get_mut(i: usize): (mut T from self)? {
        if i >= self.len { return none }
        present(unsafe { mut *self.buf.add(self.physical(i)) })
    }
    pub fn front(): (read T from self)? { self.get(0usize) }
    pub fn back(): (read T from self)? {
        if self.len == 0usize { none } else { self.get(self.len - 1usize) }
    }
    pub mut fn clear(): Unit {
        while self.len != 0usize {
            let v = self.pop_front()
        }
    }
}

extend<T, A: Allocator> Deque<T, A> implements package.core.ops.Index<usize> {
    type Output = T
    fn index(i: read usize): read T from self {
        if i >= self.len { super.alloc.panic_precondition() }
        unsafe { read *self.buf.add(self.physical(i)) }
    }
}
extend<T, A: Allocator> Deque<T, A> implements package.core.ops.IndexMut<usize> {
    type Output = T
    mut fn index_mut(i: read usize): mut T from self {
        if i >= self.len { super.alloc.panic_precondition() }
        unsafe { mut *self.buf.add(self.physical(i)) }
    }
}


// Borrowed front-to-back iterator over a ring buffer.
pub type DequeIter<region r, T, A: Allocator> { deque: read Deque<T, A> from r; index: usize }
extend<region r, T, A: Allocator> DequeIter<region r, T, A> implements Iterator {
    type Item = read T from r
    mut fn next(): (read T from r)? {
        if self.index < self.deque.len {
            let i = self.index
            self.index += 1usize
            present(unsafe { read *self.deque.buf.add(self.deque.physical(i)) })
        } else {
            none
        }
    }
}
extend<T, A: Allocator> Deque<T, A> implements Iterable {
    type Item = T
    type Iter<region r> = DequeIter<region r, T, A>
    fn iter<region r>(receiver self: read Self from r): DequeIter<region r, T, A> { DequeIter(read self, 0usize) }
}

// Mutable front-to-back iterator over a ring buffer.
pub type DequeIterMut<region r, T, A: Allocator> { deque: mut Deque<T, A> from r; index: usize }
extend<region r, T, A: Allocator> DequeIterMut<region r, T, A> implements Iterator {
    type Item = mut T from r
    mut fn next(): (mut T from r)? {
        if self.index < self.deque.len {
            let i = self.index
            self.index += 1usize
            present(unsafe { mut *self.deque.buf.add(self.deque.physical(i)) })
        } else {
            none
        }
    }
}
extend<T, A: Allocator> Deque<T, A> implements MutableIterable {
    type Item = T
    type IterMut<region r> = DequeIterMut<region r, T, A>
    fn iter_mut<region r>(receiver self: mut Self from r): DequeIterMut<region r, T, A> { DequeIterMut(mut self, 0usize) }
}

extend<T: Clone, A: Allocator + Clone> Deque<T, A> implements Clone {
    fn clone(): Deque<T, A> {
        var out = new_in<T, A>(self.a.clone())
        var i = 0usize
        while i < self.len {
            out.push_back(self[i].clone())
            i += 1usize
        }
        out
    }
}
extend<T: PartialEq, A: Allocator> Deque<T, A> implements PartialEq {
    fn eq(other: read Deque<T, A>): bool {
        if self.len != other.len { return false }
        var i = 0usize
        while i < self.len {
            if !self[i].eq(other[i]) { return false }
            i += 1usize
        }
        true
    }
}
extend<T: Eq, A: Allocator> Deque<T, A> implements Eq {}
extend<T: PartialOrd, A: Allocator> Deque<T, A> implements PartialOrd {
    fn partial_cmp(other: read Deque<T, A>): Ordering? {
        var i = 0usize
        while i < self.len && i < other.len {
            match self[i].partial_cmp(other[i]) {
                present(o) => { if !o.is_eq() { return present(o) } },
                none => { return none }
            }
            i += 1usize
        }
        self.len.partial_cmp(other.len)
    }
}
extend<T: Ord, A: Allocator> Deque<T, A> implements Ord {
    fn cmp(other: read Deque<T, A>): Ordering {
        var i = 0usize
        while i < self.len && i < other.len {
            let o = self[i].cmp(other[i])
            if !o.is_eq() { return o }
            i += 1usize
        }
        self.len.cmp(other.len)
    }
}
// Hashes like the slice of the same elements, front to back.
extend<T: Hash, A: Allocator> Deque<T, A> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit {
        state.write_usize(self.len)
        var i = 0usize
        while i < self.len {
            self[i].hash(mut state)
            i += 1usize
        }
    }
}
extend<T: fmt.Debug, A: Allocator> Deque<T, A> implements fmt.Debug {
    fn fmt<W: fmt.Write>(f: mut fmt.Formatter<W>): Unit throws fmt.Error {
        try f.debug_open("[")
        var i = 0usize
        while i < self.len {
            try f.debug_item_start(i == 0usize)
            try T.(fmt.Debug).fmt(self[i], mut f)
            try f.debug_item_end()
            i += 1usize
        }
        try f.debug_close("]", self.len == 0usize)
    }
}
extend<T, A: Allocator> Deque<T, A> implements ExtendItems<T> {
    mut fn extend<I: OwnedIterable<Item = T>>(items: take I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { self.push_back(item) }, none => { break } }
        }
    }
}
extend<T> Deque<T> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(items: take I): Deque<T> {
        var out = new<T>()
        out.extend(items)
        out
    }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<T: Transferable, A: Allocator + Transferable> Deque<T, A> implements Transferable {}
unsafe extend<T: Shareable, A: Allocator + Shareable> Deque<T, A> implements Shareable {}
