
fn next(mut index: i32): i32? {
    index += 1
    if index <= 3 { present(index) } else { none }
}
fn main() {
    var index = 0
    var sum = 0
    while let present(value) = next(index) { sum += value }
    var values = [20, 30]
    for value in mut values { value += 1 }
    if index == 4 && sum == 6 && values[0] == 21 && values[1] == 31 { 0 } else { 1 }
}
