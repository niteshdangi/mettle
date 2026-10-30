
module core { pub module ops {
    pub interface Index<I> { type Output; fn index(i: read I): read Self.Output from self; }
    pub interface IndexMut<I> { type Output; mut fn index_mut(i: read I): mut Self.Output from self; }
} }
type Cells { p: ptr<mut i32> }
extend Cells implements core.ops.Index<usize> {
    type Output = i32
    fn index(i: read usize): read i32 from self { unsafe { read *self.p.add(i) } }
}
extend Cells implements core.ops.IndexMut<usize> {
    type Output = i32
    mut fn index_mut(i: read usize): mut i32 from self { unsafe { mut *self.p.add(i) } }
}
type Holder<K, V> { cells: Cells; k: K; v: V }
extend<K, V> Holder<K, V> {
    mut fn store(i: usize, k: take K, v: take V, x: i32): Unit {
        self.cells[i] = x
        self.k = k
        self.v = v
    }
}
fn set(c: mut Cells, i: usize, x: i32): Unit { c[i] = x }
fn main() {
    var a = [0, 0, 0]
    var c = Cells(core.ptr.from_mut(a).cast<i32>())
    set(c, 1usize, 5)
    var h = Holder(c, 1, 2)
    h.store(2usize, 3, 4, 9)
    if a[1] != 5 || a[2] != 9 || h.k != 3 || h.v != 4 { return 1 }
    0
}
