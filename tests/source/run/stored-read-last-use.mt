
fn main() {
    var value = 40
    let view = read value
    let copied = view
    let observed = *copied + *view
    value = 42
    if observed == 80 && value == 42 { 0 } else { 1 }
}
