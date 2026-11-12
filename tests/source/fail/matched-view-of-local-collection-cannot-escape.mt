// expect-error: region 36:35 view region or invariant payload

module core { pub module iter {
  pub interface Iterator { type Item; mut fn next(): Self.Item?; }
  pub interface Iterable { type Item; type Iter<region r>; fn iter<region r>(receiver read self: Self from r): Self.Iter<region r>; }
} }
extern "C" {
    unsafe fn free(p: ptr<mut u8>): Unit;
}
import core.iter.{Iterator, Iterable}
type List<T> { ptr: ptr<mut T>; len: usize; cap: usize
    drop { unsafe {
        var i = 0usize
        while i < self.len { core.ptr.drop_in_place(self.ptr.add(i)); i += 1usize }
        if self.cap != 0usize { free(self.ptr.cast<u8>()) }
    } }
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
    fn iter<region r>(receiver read self: Self from r): VecIter<T, region r> { VecIter(read self, 0usize) }
}

fn bad(): (read i32 from static)? {
    let v = new_vec<i32>()
    match v.iter().next() { present(x) => present(x), none => none }
}
fn main(): i32 { 0 }
