// expect-error: ownership 6:5 mutable place

fn main(): i32 {
    var value = 0
    let closure = fn(): Unit { value += 1 }
    closure()
    value
}
