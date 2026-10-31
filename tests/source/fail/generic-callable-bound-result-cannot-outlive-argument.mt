// expect-error: region 5:5 view region or invariant payload

fn escape<F: for<region r> fn(read i32 from r): read i32 from r>(
    operation: read F, value: read i32): read i32 from static {
    return operation(value)
}
fn main(): i32 { 0 }
