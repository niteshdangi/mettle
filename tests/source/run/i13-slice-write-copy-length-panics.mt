// expect-exit: 101
fn main(): i32 {
    var destination = [0, 0]
    let source = [1, 2, 3]
    destination.write_copy_of_slice(source)
    0
}
