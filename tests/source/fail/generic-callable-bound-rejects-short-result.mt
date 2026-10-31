// expect-error: region 9:11 view region or invariant payload

fn apply<F: for<region r> fn(read i32 from r): read i32 from r>(
    operation: read F, value: read i32): read i32 from value {
    operation(value)
}
fn invalid<region outer>(
    value: read i32 from outer): read i32 from outer {
    let local = 1
    apply(fn(ignored) { read local }, value)
}
fn main(): i32 { 0 }
