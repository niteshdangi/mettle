// expect-error: macro 8:5 macro recursion limit of 256 exceeded
// expect-error-count: 1
macro forever {
    ($x:expr) => { forever!($x) };
}

fn main(): i32 {
    forever!(1)
}
