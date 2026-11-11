// expect-error: type 4:18 unsatisfied
type Box<T> { value: T }
fn gated<T>(read value: T): i32 where Box<T>: Copy { 42 }
fn main(): i32 { gated(0) - 42 }
