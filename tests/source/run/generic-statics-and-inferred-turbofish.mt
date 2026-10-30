
type List<T> { len: usize
  static fn empty(): List<T> { Self(0usize) }
  fn n(): usize { self.len } }
extend<T> List<T> {
    static fn new(): List<T> { List(0usize) }
    static fn two(): List<T> { Self(2usize) }
    static fn viaself(): List<T> { Self.new() }
    fn bump(): usize { self.n() + 1usize }
}
fn main(): i32 {
    let a: List<i32> = List.new()
    let b = List<i32>.new()
    let c: List<i32> = List.two()
    let e: List<u8> = List.viaself()
    let f = List<i32>.two()
    if a.n() == 0usize && b.n() == 0usize && c.n() == 2usize && f.bump() == 3usize && e.n() == 0usize { 0 } else { 1 }
}
