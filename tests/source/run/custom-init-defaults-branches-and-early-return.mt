
copy type Point {
    x: i32
    y: i32
    init(x: i32, early: bool = true) {
        self.x = x
        if early { self.y = 42 - x; return }
        self.y = -x
    }
    fn sum() { self.x + self.y }
}
fn main() { if Point(20).sum() == 42 && Point(20, false).sum() == 0 { 0 } else { 1 } }
