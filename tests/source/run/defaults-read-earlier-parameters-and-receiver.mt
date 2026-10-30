
fn sum(a: i32, b: i32 = a + 1, c: i32 = b + 1) { a + b + c }
type Counter { value: i32; mut fn increment(amount: i32 = self.value) { self.value += amount } }
fn main() {
    var counter = Counter(21)
    counter.increment()
    if sum(13) == 42 && sum(c: 20, a: 10, b: 12) == 42 && counter.value == 42 { 0 } else { 1 }
}
