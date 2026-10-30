// expect-error: type 3:13 no constructor of 'Box' accepts this argument shape
type Box<T: Copy> { value: T; init(value: T) { self.value = value } }
fn main() { Box<i32>() }
