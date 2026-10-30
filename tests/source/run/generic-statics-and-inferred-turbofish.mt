
type Vec<T> { len: usize
  static fn empty(): Vec<T> { Self(0usize) }
  fn n(): usize { self.len } }
impl<T> Vec<T> {
    static fn new(): Vec<T> { Vec(0usize) }
    static fn two(): Vec<T> { Self(2usize) }
    static fn viaself(): Vec<T> { Self::new() }
    fn bump(): usize { self.n() + 1usize }
}
fn main(): i32 {
    let a: Vec<i32> = Vec::new()
    let b = Vec::<i32>::new()
    let c: Vec<i32> = Vec::two()
    let e: Vec<u8> = Vec::viaself()
    let f = Vec::<i32>::two()
    if a.n() == 0usize && b.n() == 0usize && c.n() == 2usize && f.bump() == 3usize && e.n() == 0usize { 0 } else { 1 }
}
