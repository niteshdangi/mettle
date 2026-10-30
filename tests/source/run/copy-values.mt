copy type Point {
    x: i32
    y: i32
}

fn sum(point: Point): i32 {
    point.x + point.y
}

fn main(): i32 {
    let first = Point(x: 20, y: 22)
    let second = first
    if sum(first) == 42 && sum(second) == 42 {
        0
    } else {
        1
    }
}
