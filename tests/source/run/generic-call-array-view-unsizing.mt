interface SliceIndex<T: unsized> {
    type Output: unsized;
    fn index(read value: T): read Self.Output from value;
    fn index_mut(mut value: T): mut Self.Output from value;
}

fn index<T, const N: usize, I: SliceIndex<[T]>>(
    read index: I,
    read array: [T; N]
): read I.Output from array {
    I.(SliceIndex<[T]>).index(read index, read array)
}

fn index_mut<T, const N: usize, I: SliceIndex<[T]>>(
    read index: I,
    mut array: [T; N]
): mut I.Output from array {
    I.(SliceIndex<[T]>).index_mut(read index, mut array)
}

fn main(): i32 { 0 }
