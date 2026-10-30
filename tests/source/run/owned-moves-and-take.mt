
type Counter { value: i32 }
fn finish(counter: take Counter) { counter.value }
fn main() {
    var first = Counter(40)
    let second = first
    first = Counter(42)
    let _ = second
    let _ = second.value
    let observed = second.value
    let result = finish(first)
    if observed == 40 && result == 42 { 0 } else { 1 }
}
