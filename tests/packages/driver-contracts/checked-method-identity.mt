type A { fn value() { 1 } }
type B { fn value() { 2 } }
fn main(): i32 { A().value() }
