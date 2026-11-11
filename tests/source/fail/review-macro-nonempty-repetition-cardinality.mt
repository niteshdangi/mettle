// expect-error: macro 3:18 nonempty macro repetition has no elements
macro broken { ($($x:expr),*) => { $(let _ = $x;)+ }; }
fn main(): i32 { broken!(); 0 }
