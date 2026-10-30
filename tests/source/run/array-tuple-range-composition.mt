
fn main() {
    let tuple = (20, 22)
    var values: [i32; 3] = [tuple.0, tuple.1, 0]
    var sum = 0
    for index in 0..2 { sum += values[index] }
    values[2] = sum
    let [first, second, third] = values
    let (a, b) = tuple
    if a + b == 42 && first + second == third { 0 } else { 1 }
}
