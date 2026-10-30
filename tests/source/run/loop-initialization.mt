
fn main() {
    let result: i32
    loop {
        result = 42
        break
    }
    var count = 0
    while count < 3 {
        let fresh = count
        count = fresh + 1
    }
    if result == 42 && count == 3 { 0 } else { 1 }
}
