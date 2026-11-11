// expect-error: type 6:1 interface arguments do not satisfy their declared constraints
// expect-error: type 7:1 interface arguments do not satisfy their declared constraints
type NonCopy {}
interface RequiresCopy<T: Copy> {}
interface Count<const N: i32> {}
extend NonCopy implements RequiresCopy<NonCopy> {}
extend NonCopy implements Count<bool> {}
fn main(): i32 { 0 }
