
fn fallback(mut value: i32) { value += 1; 42 }
fn main() {
    var calls = 0
    let first: i32? = present(42)
    let absent: i32? = none
    let a = first ?? fallback(calls)
    let b = absent ?? fallback(calls)
    if a == 42 && b == 42 && calls == 1 { 0 } else { 1 }
}
