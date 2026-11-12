
copy type Pair { first: i32; second: i32 }
fn main() {
    var pair = Pair(20, 30)
    let first = mut pair.first
    let second = mut pair.second
    *first += 1
    *second += 2
    if pair.first == 21 && pair.second == 32 { 0 } else { 1 }
}
