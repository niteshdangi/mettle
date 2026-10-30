
alias Position = Coordinate
alias Coordinate = Point
alias Number = i32
copy type Point {
    x: Number
    y: Number
    static fn origin(): Self { Self(0, 0) }
    static fn make(x: Number, y: Number): Self { Self(x, y) }
    static fn answer() { Self.make(20, 22).sum() }
    fn sum() { self.x + self.y }
}
fn same(value: Position): Point { value }
fn main() {
    let origin = Position.origin()
    let point: Coordinate = Position.make(y: 22, x: 20)
    if same(point).sum() == 42 && Point.answer() == 42 && origin.sum() == 0 { 0 } else { 1 }
}
