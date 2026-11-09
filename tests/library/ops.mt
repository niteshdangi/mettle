import core.ops
type V { x: i32 }
extend V implements core.ops.Add<V> {
    type Output = V
    fn add(read rhs: V): V { V(self.x + rhs.x) }
}
extend V implements core.ops.AddAssign<i32> {
    mut fn add_assign(read rhs: i32): Unit { self.x += rhs }
}
extend V implements core.ops.Neg {
    type Output = V
    fn neg(): V { V(0 - self.x) }
}
type Cells { p: ptr<mut i32> }
extend Cells implements core.ops.Index<usize> {
    type Output = i32
    fn index(read i: usize): read i32 from self { unsafe { read *self.p.add(i) } }
}
fn main(): i32 {
    var a = V(1)
    let b = V(2)
    let c = a + b
    a += 4
    let d = -c
    if c.x != 3 || a.x != 5 || d.x != -3 { return 1 }
    0
}
