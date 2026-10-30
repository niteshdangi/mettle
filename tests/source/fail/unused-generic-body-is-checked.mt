// expect-error: type 2:28 expected i32, found T
fn wrong<T>(value: T): i32 { value }
fn main(): i32 { 0 }
