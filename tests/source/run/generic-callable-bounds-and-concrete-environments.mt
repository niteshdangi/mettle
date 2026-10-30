
fn apply<F: fn(i32): i32>(operation: read F, value: i32): i32 {
    operation(value)
}
fn change<F: mut fn(i32): i32>(operation: mut F, value: i32): i32 {
    operation(value)
}
fn once<F: take fn(): i32>(operation: take F): i32 { operation() }
fn identity<T>(value: take T): T { value }
fn make<T>(value: take T) { take fn(): T { take value } }
type Item { value: i32 }
fn main(): i32 {
    let value = 20
    let reader = fn(extra: i32): i32 { value + extra }
    var count = 20
    var writer = fn(extra: i32): i32 { count += extra; count }
    let item = Item(42)
    let consumer = take fn(): i32 { let owned = take item; owned.value }
    let pointer: fn(take i32): i32 = identity<i32>
    let returned = make(42)
    if apply(reader,22) == 42 && change(writer,22) == 42 &&
       once(consumer) == 42 && pointer(42) == 42 &&
       returned() == 42 { 0 } else { 1 }
}
