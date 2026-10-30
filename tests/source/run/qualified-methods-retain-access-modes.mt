
alias RoomCounter = Counter
type Counter {
    value: i32
    fn get() { self.value }
    mut fn add(value: i32) { self.value += value }
    take fn finish() { self.value }
}
fn main() {
    var counter = Counter(20)
    RoomCounter.add(counter, 22)
    let observed = Counter.get(counter)
    if observed == 42 && RoomCounter.finish(counter) == 42 { 0 } else { 1 }
}
