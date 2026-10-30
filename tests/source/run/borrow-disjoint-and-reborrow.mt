
type Counter { value: i32 }
type Pair { first: Counter; second: Counter }
fn increment(c: mut Counter) { c.value += 1 }
fn inspect(c: Counter) { c.value }
fn both(a: mut Counter, b: mut Counter) {
    increment(a)
    increment(b)
    inspect(a) + inspect(b)
}
fn main() {
    var pair = Pair(Counter(20), Counter(20))
    let result = both(pair.first, pair.second)
    if result == 42 && inspect(pair.first) == 21 { 0 } else { 1 }
}
