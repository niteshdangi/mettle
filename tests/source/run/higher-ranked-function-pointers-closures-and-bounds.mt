
fn apply<F: for<region r> fn(read i32 from r): read i32 from r>(
    read operation: F, read value: i32): read i32 from value {
    operation(value)
}
fn identity<region r>(read value: i32 from r): read i32 from r { read value }
fn main(): i32 {
    let pointer: for<region a> fn(read i32 from a): read i32 from a = identity
    let closure: for<region b> fn(read i32 from b): read i32 from b =
        fn(value) { read value }
    let value = 42
    if *apply(pointer,value) == 42 && *apply(closure,value) == 42 { 0 } else { 1 }
}
