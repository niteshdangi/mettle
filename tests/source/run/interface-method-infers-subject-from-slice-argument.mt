interface Subject<T: unsized> {
    fn get(read value: T): i32;
}
type Index {}
extend<T> Index implements Subject<[T]> {
    fn get(read value: [T]): i32 { 42 }
}
extend Index implements Subject<Text> {
    fn get(read value: Text): i32 { 1 }
}

fn main(): i32 {
    let values = [1i32, 2i32]
    let slice: read [i32] = read values
    Index().get(read values) + Index().get(slice) - 84
}
