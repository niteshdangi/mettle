// expect-exit: 0
const fn square(x: i32): i32 { x * x }
const fn factorial(n: u32): u32 { if n <= 1 { 1 } else { n * factorial(n - 1) } }
const fn gcd(a: u64, b: u64): u64 {
    var x = a;
    var y = b;
    while y != 0 {
        let t = x % y;
        x = y;
        y = t;
    }
    x
}
const fn classify(n: i32): u8 {
    match n {
        0 => 10,
        1 | 2 => 20,
        _ => 30,
    }
}

static SQUARES: [i32; 4] = [square(1), square(2), square(3), square(4)];
static FACT: u32 = factorial(10);
static GCD: u64 = gcd(1071, 462);
static KINDS: (u8, u8, u8) = (classify(0), classify(2), classify(9));
static WRAPPED: u8 = (300i32 as u8);
static SHIFT: usize = 1usize << 20;

fn main(): i32 {
    if SQUARES[3] != 16 { return 1; }
    if FACT != 3628800 { return 2; }
    if GCD != 21 { return 3; }
    if KINDS.0 != 10 || KINDS.1 != 20 || KINDS.2 != 30 { return 4; }
    if WRAPPED != 44 { return 5; }
    if SHIFT != 1048576 { return 6; }
    0
}
