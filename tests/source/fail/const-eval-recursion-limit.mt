// expect-error: limit 2:53 call depth
const fn down(n: u32): u32 { if n == 0 { 0 } else { down(n - 1) + 1 } }
static V: u32 = down(100000);
fn main(): i32 { 0 }
