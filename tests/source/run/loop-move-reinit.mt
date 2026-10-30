
type Counter { value: i32 }
fn main() {
    var counter = Counter(0)
    var n = 0
    while n < 3 {
        let previous = counter
        counter = Counter(previous.value + 1)
        n += 1
    }
    if counter.value == 3 { 0 } else { 1 }
}
