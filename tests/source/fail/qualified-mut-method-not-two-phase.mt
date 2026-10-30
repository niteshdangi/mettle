// expect-error: ownership 3:61 live exclusive loan
type Counter { value: i32; fn get() { self.value }; mut fn add(value: i32) { self.value += value } }
fn main() { var counter = Counter(1); Counter::add(counter, counter.get()); 0 }
