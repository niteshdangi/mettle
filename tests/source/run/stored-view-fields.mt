
copy type Pair { first: i32; second: i32 }
fn main() {
    var pair = Pair(20, 20)
    let first = mut pair.first
    let second = mut pair.second
    *first += 1
    *second += 1
    if pair.first + pair.second == 42 { 0 } else { 1 }
}
