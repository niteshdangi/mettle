interface Family<T: Copy> { type Item<U: Copy = T>: Copy; }
type Number {}
extend Number implements Family<i32> { type Item<U: Copy> = (U, U) }
fn main(): i32 {
    let pair: Number.(Family<i32>).Item = (21, 21)
    pair.0 + pair.1 - 42
}
