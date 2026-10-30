
type Leaf { value: i32 }
type Pair { first: Leaf; second: Leaf }
fn main() {
    var p = Pair(Leaf(20), Leaf(22))
    let first = p.first
    let observed = p.second.value
    p.first = Leaf(20)
    let completed = p
    if first.value + completed.second.value == 42 &&
        completed.first.value == 20 && observed == 22 { 0 } else { 1 }
}
