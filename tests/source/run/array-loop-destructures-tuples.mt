
fn main() {
    var sum = 0
    for (first, second) in [(10, 11), (10, 11)] { sum += first + second }
    if sum == 42 { 0 } else { 1 }
}
