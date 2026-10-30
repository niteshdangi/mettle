copy type Point {
    x: i32
    y: i32

    fn sum(): i32 {
        self.x + self.y
    }
}

fn make_point(x: i32, y: i32 = 2): Point {
    Point(x: x, y: y)
}

fn main(): i32 {
    let point = make_point(40)
    if point.sum() == 42 {
        0
    } else {
        1
    }
}
