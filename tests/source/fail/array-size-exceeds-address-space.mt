// expect-error: limit 2:6 array size exceeds target address space
fn f(a:[[u64;2_000_000_000];2_000_000_000]) {}
fn main() { 0 }
