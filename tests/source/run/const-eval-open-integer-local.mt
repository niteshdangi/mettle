// expect-exit: 0
const fn sum_to(n: u64): u64 {
    var i = 0;
    var total = 0;
    while i < n {
        total += i;
        i += 1;
    }
    total
}
const fn widen(): u64 {
    var x = 4000000000;
    x += 1;
    x
}
static SUM: u64 = sum_to(100000)
static WIDE: u64 = widen()

fn main(): i32 {
    if SUM != 4999950000 { return 1; }
    if WIDE != 4000000001 { return 2; }
    0
}
