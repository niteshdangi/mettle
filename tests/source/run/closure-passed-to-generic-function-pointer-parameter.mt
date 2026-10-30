
fn apply<B>(f: take fn(i32): B): B { f(1) }
fn main(): i32 { apply::<i32>(fn(x: i32): i32 { x + 1 }) - 2 }
