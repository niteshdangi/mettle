
copy type Pair { first: i32; second: i32 }
fn choose(flag: bool) {
    loop {
        if flag { break Pair(20, 22) }
        break Pair(21, 21)
    }
}
fn truth() { loop { break true } }
fn main() {
    let first = choose(true)
    let second = choose(false)
    if truth() && first.first + first.second == 42 && second.first + second.second == 42 { 0 } else { 1 }
}
