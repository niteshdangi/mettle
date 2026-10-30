
fn sum(v: read [u8]): i32 { var t = 0; for x in v { t += x as i32 }; t }
fn main(): i32 {
    let a: read [u8; 3] from static = b"abc"
    let r: read [u8] = br"x\y"
    let e = b"\x00\xff\n"
    let s: read [u8] = a
    if sum(s) != 97 + 98 + 99 || r.len() != 3usize || e[1] != 255u8 { return 1 }
    0
}
