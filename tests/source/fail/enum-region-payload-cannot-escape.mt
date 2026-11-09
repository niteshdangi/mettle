// expect-error: region 5:5 view region or invariant payload
enum Choice<region r> { Empty, Value(read i32 from r) }
fn invalid<region r>(read source: i32 from r): Choice<region r> {
    let value = 7
    return Choice.Value(read value)
}
fn main(): i32 { 0 }
