
copy type Pair { x: i32; y: i32 }
fn main() {
    var p = Pair(1, 2)
    p.x += { p.x = 5; 1 }
    (p.y) = p.x * 7
    if p.x == 6 && p.y == 42 { 0 } else { 1 }
}
