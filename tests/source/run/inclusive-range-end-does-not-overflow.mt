
fn main() {
    var count = 0
    for value in 2147483646..=2147483647 { count += 1 }
    for value in 4..2 { return 1 }
    if count == 2 { 0 } else { 1 }
}
