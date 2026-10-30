
copy type Pair { x: i32; y: i32 }
fn sum(p: Pair) { p.x + p.y }
fn choose(flag: bool) {
    let p: Pair
    if flag { p.x = 40 } else { p.x = 41 }
    p.y = 2
    sum(p)
}
fn main() { if choose(true) == 42 && choose(false) == 43 { 0 } else { 1 } }
