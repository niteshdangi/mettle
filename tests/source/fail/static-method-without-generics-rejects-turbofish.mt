// expect-error-count: 1
// expect-error: type 5:34 excess explicit generic arguments
type V<T> { n: usize
  static fn make(): V<T> { V(0usize) } }
fn main(): i32 { let v: V<i32> = V::make::<i32>(); 0 }
