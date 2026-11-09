// expect-error: region 10:5 declared relationship

fn apply<F: for<region r> fn(read i32 from r): read i32 from r>(
    read operation: F, read value: i32): read i32 from value {
    operation(value)
}
fn invalid<region outer>(
    operation: fn(read i32 from outer): read i32 from outer,
    read value: i32 from outer): read i32 from value {
    apply(operation,value)
}
fn main(): i32 { 0 }
