// expect-error: type 4:10 associated family arguments do not satisfy their declared constraints
interface Family { type Item<F: fn(read i32): i32>; }
fn invalid<T: Family>(
    take value: T.(Family).Item<fn(read i32): bool>
): Unit { let _ = value }
fn main(): i32 { 0 }
