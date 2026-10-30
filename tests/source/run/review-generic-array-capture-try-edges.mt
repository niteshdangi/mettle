
fn checked(value:i32):i32 throws i32 {
    if value > 5 { throw value }
    value
}
fn scan<const N:i32>(values:read [i32;N]):i32 {
    let outcome = capture {
        var total = 0
        for value in values { total += try checked(value) }
        total
    }
    match outcome { success(total) => total, failure(value) => value }
}
fn main() {
    let first = [1,2,3]
    let second = [1,7,3]
    if scan(first) == 6 && scan(second) == 7 { 0 } else { 1 }
}
