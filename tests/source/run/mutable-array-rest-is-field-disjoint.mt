
fn main() {
    var values = [20, 30, 40]
    match mut values {
        [first, middle @ ..] => { first += 1; middle[0] += 2 }
    }
    if values[0] == 21 && values[1] == 32 && values[2] == 40 { 0 } else { 1 }
}
