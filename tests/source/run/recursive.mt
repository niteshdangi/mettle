
fn odd(n: i32) {
    if n == 0 { false } else { even(n - 1) }
}
fn even(n: i32) {
    if n == 0 { true } else { odd(n - 1) }
}
fn main() { if even(10) && odd(9) { 0 } else { 1 } }
