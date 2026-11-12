
copy type Pair { first: i32; second: i32 }
fn choose(flag: bool) {
    loop {
        if flag { break Pair(20, 22) }
        break Pair(19, 23)
    }
}
fn truth() { loop { break true } }
fn main() {
    let first = choose(true)
    let second = choose(false)
    if truth() && first.first == 20 && first.second == 22 &&
       second.first == 19 && second.second == 23 { 0 } else { 1 }
}
