
fn main() {
    var values = [20, 20, 0]
    match mut values {
        [first, middle @ ..] => { first += 1; middle[0] += 1 }
    }
    if values[0] + values[1] == 42 { 0 } else { 1 }
}
