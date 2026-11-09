
copy type Pair { x: i32; y: i32 }
fn consume(take value: i32) { value }
fn main() {
    var p = Pair(20, 22)
    let x = take p.x
    p.x = x
    let _ = consume(p.y)
    p.y = 22
    if p.x + p.y == 42 { 0 } else { 1 }
}
