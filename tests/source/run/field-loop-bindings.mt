
copy type Pair { x: i32; y: i32 }
fn sum(p: Pair) { p.x + p.y }
fn main() {
    var n = 0
    var total = 0
    while n < 3 {
        let p: Pair
        p.x = n
        p.y = 1
        total += sum(p)
        n += 1
    }
    if total == 6 { 0 } else { 1 }
}
