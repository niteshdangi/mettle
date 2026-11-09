// profiles: debug release
fn main(): i32 {
    var values = [2i32, 4i32, 6i32]
    if values.as_slice().len() != 3usize || values.as_slice()[1usize] != 4i32 {
        return 1
    }
    values.as_mut_slice()[1usize] = 9i32
    if values[1usize] != 9i32 { return 2 }
    0
}
