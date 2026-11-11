fn apply<F: for<region r> fn(read i32 from r): read i32 from r>(
    read operation: F, read value: i32): read i32 from value {
    operation(value)
}
fn identity<region r>(read value: i32 from r): read i32 from r {
    read value
}
fn forward<G: for<region s> fn(read i32 from s): read i32 from s>(
    read operation: G, read value: i32): read i32 from value {
    apply(operation, value)
}
fn main(): i32 {
    let value = 42
    let forwarded = *forward(identity, value)
    if *apply(identity, value) == 42 && forwarded == 42 { 0 } else { 1 }
}
