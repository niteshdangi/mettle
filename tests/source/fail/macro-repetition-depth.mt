// expect-error: macro 3:25 bound 1 repetition level(s) deep but used at depth 0
macro broken {
    ($($x:expr),*) => { $x };
}
fn main(): i32 { 0 }
