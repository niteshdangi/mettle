// expect-error: ownership 6:22 live exclusive loan
fn main(): i32 {
    var values = [1u8, 2u8]
    var window = mut values[..]
    let first = mut (*window)[0usize]
    let second = mut (*window)[0usize]
    *first = 3u8
    *second = 4u8
    0
}
