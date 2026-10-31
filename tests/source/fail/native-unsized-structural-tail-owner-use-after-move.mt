// expect-error: ownership 11:5 moved
type Tail<T: unsized> {
    header: i32
    values: T
}

fn main(): i32 {
    let sized: heap Tail<[i32; 2]> = heap Tail(7, [1, 2])
    let first: heap Tail<[i32]> = sized
    let second = first
    first.get().header
    0
}
