// expect-error: type 5:18 interface
interface Ready {}
type Box<T> { value: T }
fn gated<T>(read value: T): i32 where Box<T>: Ready { 42 }
fn main(): i32 { gated(0) - 42 }
