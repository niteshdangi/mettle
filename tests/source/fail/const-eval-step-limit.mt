// expect-error: limit 4:15 step budget
const fn spin(n: u64): u64 {
    var i: u64 = 0;
    while i < n { i = i + 1; }
    i
}
static V: u64 = spin(100000000000)
fn main(): i32 { 0 }
