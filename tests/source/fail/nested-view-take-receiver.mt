// expect-error: ownership 8:5 cannot move out of a borrowed place

type Counter { value: i32; take fn consume() {} }
fn main() {
    let counter = Counter(42)
    let first = read counter
    let second = read first
    second.consume()
    0
}
