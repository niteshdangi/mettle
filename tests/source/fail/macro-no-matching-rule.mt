// expect-error: macro 8:5 no rule of macro 'pair' matches
// expect-error-count: 1
macro pair {
    ($a:expr, $b:expr) => { $a + $b };
}

fn main(): i32 {
    pair!(1, 2, 3)
}
