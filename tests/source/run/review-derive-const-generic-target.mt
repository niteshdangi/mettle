import core.clone.Clone
@derive(Clone)
type Buffer<const N: usize> { values: [i32; N] }
fn main(): i32 {
    let original = Buffer<3>([1, 2, 3])
    let duplicate = original.clone()
    duplicate.values[2usize] - 3
}
