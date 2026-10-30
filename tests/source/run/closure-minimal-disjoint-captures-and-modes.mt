
copy type Pair { first: i32; second: i32 }
fn main(): i32 {
    var pair = Pair(20,1)
    let read_first = fn(): i32 { pair.first }
    pair.second += 1
    var mutate_second = fn(value: i32): i32 {
        pair.second += value
        pair.second
    }
    let owned = take fn(value: i32): i32 { read_first() + value }
    let first = mutate_second(18)
    let second = mutate_second(2)
    if first == 20 && second == 22 && owned(22) == 42 &&
       owned(0) == 20 { 0 } else { 1 }
}
