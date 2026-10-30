
fn main() {
    var value = 40
    let parent = mut value
    let child = mut *parent
    *child += 1
    *parent += 1
    if value == 42 { 0 } else { 1 }
}
