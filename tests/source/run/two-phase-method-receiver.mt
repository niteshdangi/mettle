
type Counter {
    value: i32
    fn get() { self.value }
    mut fn add(value: i32) { self.value += value }
}
fn main() {
    var counter = Counter(21)
    counter.add(counter.get())
    if counter.value == 42 { 0 } else { 1 }
}
