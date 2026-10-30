
fn main() {
    let a = -2_147_483_648i32
    let b = -(2147483648)
    if a == b && (a >> 31) == -1 && !false && !0 == -1 { 0 } else { 1 }
}
