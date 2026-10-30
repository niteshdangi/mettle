// expect-error: macro 3:6 fragment '$x:expr' cannot be followed by '+'
macro broken {
    ($x:expr + $y:expr) => { $x };
}
fn main(): i32 { 0 }
