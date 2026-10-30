// expect-error: type 5:5 expected fn()

fn main(): i32 {
    let value = 42
    let pointer: fn(): i32 = fn() { value }
    pointer()
}
