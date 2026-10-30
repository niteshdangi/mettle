
copy type Pair {
    first: i32
    second: i32
}
fn main() {
    var state = 0
    let pair = Pair(second: { state = 2; state }, first: { state += 1; state })
    if pair.first == 3 && pair.second == 2 && state == 3 { 0 } else { 1 }
}
