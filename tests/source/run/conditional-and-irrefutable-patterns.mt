
fn inspect_presence(value: i32?) { let present(answer) = value else { return 0 }; answer }
fn main() {
    let pair = (20, 22)
    let (a, b) = pair
    let result = if let present(value) = present(a + b) { value } else { 0 }
    if result == 42 && inspect_presence(present(42)) == 42 && inspect_presence(none) == 0 { 0 } else { 1 }
}
