
copy type Counter {
    value: i32
    fn get(extra: i32) { self.value + extra }
    mut fn increment() { self.value += 1 }
}
fn mark(log: mut i32) { log += 1; 0 }
fn main() {
    var log = 0
    let absent: Counter? = none
    var present_counter: Counter? = present(Counter(41))
    let skipped = absent?.get(mark(log))
    let _ = present_counter?.increment()
    let answer = present_counter?.get(mark(log))
    if log == 1 && (answer ?? 0) == 42 && (skipped ?? 0) == 0 &&
       (present_counter?.value ?? 0) == 42 { 0 } else { 1 }
}
