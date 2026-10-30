// expect-error: parse 4:23 expected ':'

fn main(): i32 {
    let closure: fn() = fn() { 42 }
    closure()
}
