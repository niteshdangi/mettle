// expect-error: macro 3:25 unbound metavariable '$y'
macro broken {
    ($x:expr) => { $x + $y };
}
fn main(): i32 { 0 }
