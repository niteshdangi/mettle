// expect-error: ownership 11:5 access or storage conflicts with a live exclusive loan

enum Choice<region r> { Empty, Value(mut i32 from r) }
fn choose<region r>(mut source: i32 from r, ready: bool): Choice<region r> {
    if ready { return Choice.Value(mut source) }
    Choice.Empty
}
fn main(): i32 {
    var value = 0
    let result = choose(mut value,true)
    value = 1
    match take result {
        Choice.Empty => 0,
        Choice.Value(pointer) => *pointer
    }
}
