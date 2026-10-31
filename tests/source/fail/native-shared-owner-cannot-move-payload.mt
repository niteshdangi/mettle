// expect-error: ownership 5:22 cannot move out of a borrowed place
type Value { value: i32 }
fn main() {
    let owner = shared Value(7)
    let moved = take *owner.get()
    0
}
