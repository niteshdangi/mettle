
type Counter { value: i32 }
fn inspect(c: Counter) { c.value }
fn increment(mut c: Counter) { c.value += 1; c.value }
fn main() {
    if inspect(Counter(42)) == 42 && increment(Counter(41)) == 42 { 0 } else { 1 }
}
