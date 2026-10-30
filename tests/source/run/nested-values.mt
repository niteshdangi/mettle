
fn main() {
    let x = if true {
        if false { 1 } else { 40 }
    } else { 2 }
    let y = { let a = 1; a + 1 }
    if x + y == 42 { 0 } else { 1 }
}
