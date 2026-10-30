
copy type Value {
    value: i32
    fn checked(): i32 throws i32 { if self.value < 0 { throw 7 }; self.value }
}
fn main() {
    let valid: Value? = present(Value(42))
    let invalid: Value? = present(Value(-1))
    let absent: Value? = none
    let good = capture valid?.checked()
    let bad = capture invalid?.checked()
    let empty = capture absent?.checked()
    let answer = match good { success(value) => value ?? 0, failure(_) => 0 }
    let failed = match bad { success(_) => false, failure(error) => error == 7 }
    let skipped = match empty { success(none) => true, success(present(_)) => false, failure(_) => false }
    if answer == 42 && failed && skipped { 0 } else { 1 }
}
