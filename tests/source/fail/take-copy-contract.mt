// expect-error: ownership 8:5 moved
fn consume(take value: i32): Unit {
}

fn main(): i32 {
    let value = 42
    consume(value)
    value
}
