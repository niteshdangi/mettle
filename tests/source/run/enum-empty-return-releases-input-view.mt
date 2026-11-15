enum Choice<region r> { Empty, Value(mut i32 from r) }
fn empty<region r>(mut source: i32 from r): Choice<region r> {
    Choice.Empty
}
fn forward<region r>(mut source: i32 from r): Choice<region r> {
    empty(mut source)
}
fn main(): i32 {
    var value = 0
    let result = forward(mut value)
    value = 1
    match take result {
        Choice.Empty => value - 1,
        Choice.Value(_) => 2
    }
}
