fn apply<F: for<region r> fn(read i32 from r): read i32 from r>(
    operation: read F, value: read i32): read i32 from value {
    operation(value)
}
fn identity<region r>(value: read i32 from r): read i32 from r {
    read value
}
fn main(): i32 {
    let value = 42
    if *apply(identity, value) == 42 { 0 } else { 1 }
}
