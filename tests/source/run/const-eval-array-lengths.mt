// expect-exit: 0
const fn lanes(n: usize): usize { n * 2 + 1 }
const LEN: usize = lanes(3)
const AREA: usize = if LEN > 4 { LEN * LEN } else { 0 };

fn main(): i32 {
    let a: [u8; LEN] = [7; LEN];
    let b: [i32; AREA] = [1; AREA];
    if a[6] != 7 { return 1; }
    if b[48] != 1 { return 2; }
    0
}
