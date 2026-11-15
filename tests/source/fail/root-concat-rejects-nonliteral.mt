// expect-error: macro 5:19 concat! operands must be supported literals

fn main(): i32 {
    let value = 7i32
    let invalid = concat!(value)
    0
}
