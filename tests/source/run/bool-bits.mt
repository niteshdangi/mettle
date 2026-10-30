
fn main() {
    var value = true
    value &= false
    value |= true
    value ^= false
    if value && false < true && true >= false { 0 } else { 1 }
}
