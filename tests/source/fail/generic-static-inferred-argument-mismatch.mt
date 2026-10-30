// expect-error: type 4:50 expected Vec<u8>, found Vec<i32>
type Vec<T> { len: usize
  static fn empty(): Vec<T> { Self(0usize) } }
fn main(): i32 { let a: Vec<i32> = Vec::empty(); let b: Vec<u8> = a; 0 }
