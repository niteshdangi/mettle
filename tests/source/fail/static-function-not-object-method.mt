// expect-error: type 3:34 type-qualified call
copy type Point { static fn make() { 42 } }
fn main() { let point = Point(); point.make() }
