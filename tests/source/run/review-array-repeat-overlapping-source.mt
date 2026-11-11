fn main(): i32 {
    var values = [[7u8; 1025]; 65]
    values = [values[0usize]; 65]
    if values[0usize][0usize] == 7u8 && values[64usize][1024usize] == 7u8 {
        0
    } else {
        1
    }
}
