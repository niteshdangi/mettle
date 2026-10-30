// expect-error: type 3:13 no constructor of 'Number' accepts this argument shape
type Number { value: i32; init(value: i32) { self.value = value } }
fn main() { Number() }
