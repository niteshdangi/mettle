fn identity<T: Copy>(value: T): T { value }
fn main(): i32 { identity<i32>(value: 42) }
