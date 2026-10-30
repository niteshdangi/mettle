// expect-error: type 5:5 overlapping constructor argument shapes
type Number {
    value: i32
    init(value: i32, extra: i32 = 1) { self.value = value + extra }
    init(other: bool) { self.value = if other { 1 } else { 0 } }
}
fn main() { 0 }
