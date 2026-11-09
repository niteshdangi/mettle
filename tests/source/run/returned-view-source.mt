
fn identity(read value: i32): read i32 from value { read value }
fn main() {
    var value = 40
    let view = identity(value)
    let observed = *view
    value = 42
    if observed == 40 && value == 42 { 0 } else { 1 }
}
