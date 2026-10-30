
type Counter {
    value: i32
    fn get() { self.value }
    mut fn add(value: i32) { self.value += value }
}
fn main() {
    var counter = Counter(21)
    { let first = read counter; let second = read first; if second.get() != 21 { return 1 } }
    { var first = mut counter; let second = mut first; second.add(second.get()) }
    if counter.value == 42 { 0 } else { 1 }
}
