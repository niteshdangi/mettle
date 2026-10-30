
fn next(index: mut i32): i32? {
    index += 1
    if index <= 3 { present(index) } else { none }
}
fn main() {
    var index = 0
    var sum = 0
    while let present(value) = next(index) { sum += value }
    var values = [20, 20]
    for value in mut values { value += 1 }
    if sum == 6 && values[0] + values[1] == 42 { 0 } else { 1 }
}
