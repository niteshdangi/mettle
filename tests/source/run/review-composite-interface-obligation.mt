interface Ready {}
type Box<T> { value: T }
extend Box<i32> implements Ready {}
fn gated<T>(read value: T): i32 where Box<T>: Ready { 42 }
fn forward<T>(read value: T): i32 where Box<T>: Ready { gated(value) }
fn main(): i32 { forward(0) - 42 }
