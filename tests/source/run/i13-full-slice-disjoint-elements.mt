// profiles: debug release
fn main(): i32 {
    var values = [1u8, 2u8]
    var window = mut values[..]
    let first = mut (*window)[0usize]
    let second = mut (*window)[1usize]
    *first = 3u8
    *second = 4u8
    if *first != 3u8 || *second != 4u8 { return 1 }
    0
}
