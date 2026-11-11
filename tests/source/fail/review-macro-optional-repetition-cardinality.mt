// expect-error: macro 3:18 optional macro repetition has more than one element
macro broken { ($($x:expr),*) => { $(let _ = $x;)? }; }
fn main(): i32 { broken!(1, 2); 0 }
