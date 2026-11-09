
module core { pub module iter {
  pub interface Iterator { type Item; mut fn next(): Self.Item?; }
  pub interface Iterable { type Item; type Iter<region r>; fn iter<region r>(receiver self: read Self from r): Self.Iter<region r>; }
  pub interface MutableIterable { type Item; type IterMut<region r>; fn iter_mut<region r>(receiver self: mut Self from r): Self.IterMut<region r>; }
} }
extern "C" {
    unsafe fn realloc(p: ptr<mut u8>, n: usize): ptr<mut u8>;
    unsafe fn free(p: ptr<mut u8>): Unit;
}
import core.iter.{Iterator, Iterable, MutableIterable}
type List<T> { ptr: ptr<mut T>; len: usize; cap: usize
    drop { unsafe {
        var i = 0usize
        while i < self.len { core.ptr.drop_in_place(self.ptr.add(i)); i += 1usize }
        if self.cap != 0usize { free(self.ptr.cast<u8>()) }
    } }
}
extend<T> List<T> {
    mut fn push(v: take T): Unit {
        if self.len == self.cap {
            let nc = if self.cap == 0usize { 4usize } else { self.cap * 2usize }
            let np = unsafe { realloc(self.ptr.cast<u8>(), nc * core.mem.size_of<T>()) }
            self.ptr = np.cast<T>()
            self.cap = nc
        }
        unsafe { core.ptr.write(self.ptr.add(self.len), v) }
        self.len += 1usize
    }
}
fn new_vec<T>(): List<T> { List(core.ptr.null_mut<T>(), 0usize, 0usize) }
type VecIter<T, region r> { v: read List<T> from r; i: usize }
extend<T, region r> VecIter<T, region r> implements Iterator {
    type Item = read T from r
    mut fn next(): (read T from r)? {
        if self.i < self.v.len {
            let x = unsafe { read *self.v.ptr.add(self.i) }
            self.i += 1usize
            present(x)
        } else { none }
    }
}
extend<T> List<T> implements Iterable {
    type Item = T
    type Iter<region r> = VecIter<T, region r>
    fn iter<region r>(receiver self: read Self from r): VecIter<T, region r> { VecIter(read self, 0usize) }
}

type VecIterMut<T, region r> { v: mut List<T> from r; i: usize }
extend<T, region r> VecIterMut<T, region r> implements Iterator {
    type Item = mut T from r
    mut fn next(): (mut T from r)? {
        if self.i < self.v.len {
            let x = unsafe { mut *self.v.ptr.add(self.i) }
            self.i += 1usize
            present(x)
        } else { none }
    }
}
extend<T> List<T> implements MutableIterable {
    type Item = T
    type IterMut<region r> = VecIterMut<T, region r>
    fn iter_mut<region r>(receiver self: mut Self from r): VecIterMut<T, region r> { VecIterMut(mut self, 0usize) }
}
type Cursor<region r> { v: mut List<i32> from r }
extend<region r> Cursor<region r> {
    fn peek(): read i32 from r { unsafe { read *self.v.ptr } }
    mut fn grow(x: i32): Unit { self.v.push(x) }
}
type Wrap<region q, region r> { c: mut Cursor<region r> from q }
type SharedCursor<region r> { v: read List<i32> from r }
extend<region r> SharedCursor<region r> {
    fn peek(): read i32 from r { unsafe { read *self.v.ptr } }
}
fn first<T>(c: read List<T>): (read T from c)? {
    var it = c.iter()
    it.next()
}

fn stored_read_before_mutation(): i32 {
    var v = new_vec<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    let a = cur.peek()
    let b = cur.peek()
    let sum = *a + *b
    cur.v.push(2)
    cur.grow(3)
    if sum != 2 { return 1 }
    0
}

fn nested_read_before_mutation(): i32 {
    var v = new_vec<i32>()
    v.push(1)
    var c = Cursor(mut v)
    var w = Wrap(mut c)
    let a = w.c.peek()
    let x = *a
    w.c.v.push(2)
    if x != 1 { return 1 }
    0
}

fn shared_reborrows_coexist(): i32 {
    var v = new_vec<i32>()
    var cur = Cursor(mut v)
    let x = read cur.v
    let y = read cur.v
    if x.len != 0usize || y.len != 0usize { return 1 }
    0
}

fn read_per_loop_iteration(): i32 {
    var v = new_vec<i32>()
    v.push(1)
    var cur = Cursor(mut v)
    var sum = 0
    var i = 0
    while i < 3 { let a = cur.peek(); sum += *a; cur.grow(i + 0); i += 1 }
    if sum != 3 { return 1 }
    0
}

fn shared_read_results_coexist(): i32 {
    var v = new_vec<i32>()
    v.push(1)
    let cur = SharedCursor(read v)
    let a = cur.peek()
    let b = cur.peek()
    if *a != 1 || *b != 1 || cur.v.len != 1usize { return 1 }
    0
}

fn local_iterator_result_returned(): i32 {
    var v = new_vec<i32>()
    v.push(4)
    match first(read v) {
        present(x) => { if *x != 4 { return 1 } },
        none => { return 1 }
    }
    0
}

fn main(): i32 {
    if stored_read_before_mutation() != 0 { return 1 }
    if nested_read_before_mutation() != 0 { return 2 }
    if shared_reborrows_coexist() != 0 { return 3 }
    if read_per_loop_iteration() != 0 { return 4 }
    if shared_read_results_coexist() != 0 { return 5 }
    if local_iterator_result_returned() != 0 { return 6 }
    0
}
