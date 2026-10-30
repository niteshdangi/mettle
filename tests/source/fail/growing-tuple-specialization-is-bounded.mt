// expect-error: limit 2:62 grows beyond the compiler size limit
fn grow<T: Copy>(v: T, n: i32): i32 { if n == 0 { 0 } else { grow((v, v), n - 1) } }
fn main(): i32 { grow(1, 64) }
