// expect-error: ownership 9:5 cannot store a view of local storage into caller-owned storage

type V<T> { p: ptr<mut T>; n: usize }
impl<T> V<T> {
    mut fn push(value: take T) { unsafe { core::ptr::write(self.p.add(self.n), value) }; self.n = self.n + 1usize }
}
fn leak(v: mut V<read i32>) {
    let y = 2
    v.push(read y)
}
fn main() { 0 }
