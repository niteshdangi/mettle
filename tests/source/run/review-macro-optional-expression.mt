macro maybe { ($($value:expr)?) => { 0 }; }
fn main(): i32 { maybe!() + maybe!(3) }
