
fn combine(first: i32, second: i32) { first * 10 + second }
fn main() {
    var state = 0
    let result = combine(
        second: { state = 2; state },
        first: { state += 1; state }
    )
    if result == 32 && state == 3 { 0 } else { 1 }
}
