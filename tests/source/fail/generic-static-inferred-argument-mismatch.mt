// expect-error: type 4:51 expected List<u8>, found List<i32>
type List<T> { len: usize
  static fn empty(): List<T> { Self(0usize) } }
fn main(): i32 { let a: List<i32> = List.empty(); let b: List<u8> = a; 0 }
