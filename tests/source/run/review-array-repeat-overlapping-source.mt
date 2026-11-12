fn main(): i32 {
    var values = [[7u8; 1025]; 65]
    values[0usize][0usize] = 11u8
    values[0usize][1024usize] = 13u8
    values[64usize][0usize] = 17u8
    values = [values[0usize]; 65]
    var row = 0usize
    while row < 65usize {
        var column = 0usize
        while column < 1025usize {
            let expected = if column == 0usize { 11u8 } else if column == 1024usize { 13u8 } else { 7u8 }
            if values[row][column] != expected { return 1 }
            column += 1usize
        }
        row += 1usize
    }
    0
}
