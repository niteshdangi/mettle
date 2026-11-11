// expect-error: type 8:10 associated family arguments do not satisfy their declared constraints
// expect-error: type 11:10 associated family arguments do not satisfy their declared constraints
interface Family {
    type Item<T>;
    type Values<const N: i32>;
}
fn missing<F: Family>(
    take value: F.(Family).Item
): Unit { let _ = value }
fn wrong_kind<F: Family>(
    take value: F.(Family).Values<bool>
): Unit { let _ = value }
fn main(): i32 { 0 }
