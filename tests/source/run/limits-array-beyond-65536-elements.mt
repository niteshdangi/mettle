
static TABLE: [u8;70000] = [3;70000];
fn main(): i32 {
    var big = [1u8; 100000]
    big[99999] = 7
    if big[99999] != 7 { return 1 }
    if big[0] != 1 { return 2 }
    if TABLE[69999] != 3 { return 3 }
    0
}
