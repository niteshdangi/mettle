
fn increment(value: i32): i32 { value + 1 }
fn apply(operation: fn(i32): i32, value: i32): i32 { operation(value) }
fn change(mut value: i32): Unit { value += 1 }
fn main(): i32 {
    let pointer: fn(i32): i32 = increment
    let contextual: fn(i32): i32 = fn(value) { value + 1 }
    let inferred = fn(value) { value }
    let local_closure = fn(value: i32): i32 { value + 1 }
    let optional: (fn(i32): i32)? = local_closure
    let update: fn(mut i32): Unit = change
    var value = 39
    update(value)
    let answer = match optional { present(operation) => operation(41), none => 0 }
    if apply(pointer,value) + contextual(0) == 42 &&
       inferred(42) == 42 && answer == 42 { 0 } else { 1 }
}
