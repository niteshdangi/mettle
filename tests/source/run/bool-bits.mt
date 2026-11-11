
fn main() {
    var value = true
    value &= false
    if value { return 1 }
    value |= true
    if !value { return 2 }
    value ^= false
    if !value { return 3 }
    value ^= true
    if !value && false < true && true >= false { 0 } else { 4 }
}
