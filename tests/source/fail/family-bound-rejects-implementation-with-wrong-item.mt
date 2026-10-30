// expect-error: type 70:1 associated item does not satisfy its interface bounds

module core { pub module iter {
  pub interface Iterator { type Item; mut fn next(): Self.Item?; }
  pub interface Iterable { type Item; type Iter<region r>: Iterator<Item = read Self.Item from r>; fn iter<region r>(receiver self: read Self from r): Self.Iter<region r>; }
  pub interface IterableMut { type Item; type IterMut<region r>: Iterator<Item = mut Self.Item from r>; fn iter_mut<region r>(receiver self: mut Self from r): Self.IterMut<region r>; }
} }
extern "C" {
    unsafe fn realloc(p: ptr<mut u8>, n: usize): ptr<mut u8>;
    unsafe fn free(p: ptr<mut u8>): Unit;
}
import core.iter.{Iterator, Iterable, IterableMut};
type Vec<T> { ptr: ptr<mut T>; len: usize; cap: usize
    drop { unsafe {
        var i = 0usize
        while i < self.len { core.ptr.drop_in_place(self.ptr.add(i)); i += 1usize }
        if self.cap != 0usize { free(self.ptr.cast<u8>()) }
    } }
}
extend<T> Vec<T> {
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
fn new_vec<T>(): Vec<T> { Vec(core.ptr.null_mut<T>(), 0usize, 0usize) }
type VecIter<T, region r> { v: read Vec<T> from r; i: usize }
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
extend<T> Vec<T> implements Iterable {
    type Item = T
    type Iter<region r> = VecIter<T, region r>
    fn iter<region r>(receiver self: read Self from r): VecIter<T, region r> { VecIter(read self, 0usize) }
}

type VecIterMut<T, region r> { v: mut Vec<T> from r; i: usize }
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
extend<T> Vec<T> implements IterableMut {
    type Item = T
    type IterMut<region r> = VecIterMut<T, region r>
    fn iter_mut<region r>(receiver self: mut Self from r): VecIterMut<T, region r> { VecIterMut(mut self, 0usize) }
}

type Bad { n: i32 }
extend Bad implements core.iter.Iterator { type Item = i32; mut fn next(): i32? { none } }
type Box { n: i32 }
extend Box implements core.iter.Iterable {
    type Item = i32
    type Iter<region r> = Bad
    fn iter<region r>(receiver self: read Self from r): Bad { Bad(0) }
}
fn main(): i32 { 0 }
