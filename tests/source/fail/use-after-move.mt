// expect-error: ownership 9:5 moved
type Counter {
    value: i32
}

fn main(): i32 {
    let first = Counter(42)
    let second = first
    first.value
}
