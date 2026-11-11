// expect-error: type 6:10 associated family arguments do not satisfy their declared constraints
interface Family {
    type Item<T: Copy>: Copy;
}
fn duplicate<F: Family, T>(
    take value: F.(Family).Item<T>
): Unit { let first = value; let second = value }
fn main(): i32 { 0 }
