
copy type Pair { first: i32; second: i32 }
static PAIR: Pair = Pair(second: 22,first: 20)
static ELEMENT: read i32 from static = read PAIR.second
static VALUES: [i32;2] = [20,22];
static SELECTED: i32 = PAIR.second
static INDEXED: i32 = VALUES[1]
static NEGATIVE: i64 = -9223372036854775808i64
static REAL: f64 = 1.25f64
static mut COUNT: i32 = 1
static MUT_ADDRESS: ptr<mut i32> = unsafe { core.ptr.from_mut(COUNT) };
fn main() {
    unsafe { *MUT_ADDRESS = 42 }
    let before = PAIR.first
    let PAIR = 42
    if before + *ELEMENT == PAIR && VALUES[0] + VALUES[1] == 42 &&
       SELECTED == 22 && INDEXED == 22 &&
       NEGATIVE == -9223372036854775808i64 && REAL == 1.25f64 &&
       unsafe { COUNT == 42 } { 0 } else { 1 }
}
