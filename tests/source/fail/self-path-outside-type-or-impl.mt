// expect-error-count: 1
// expect-error: name 5:29 'Self' is only available inside a type or extend body
type V { n: usize
  static fn make(): V { V(0usize) } }
fn main(): i32 { let v: V = Self.make(); 0 }
