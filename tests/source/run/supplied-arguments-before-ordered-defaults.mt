
fn mark(mut log: i32, digit: i32) { log = log * 10 + digit; digit }
fn ordered(mut log: i32, a: i32, b: i32 = mark(log, 2), c: i32 = mark(log, 3)) { a + b + c }
fn main() {
    var log = 0
    let value = ordered(a: mark(mut log, 1), log: mut log)
    if log == 123 && value == 6 { 0 } else { 1 }
}
