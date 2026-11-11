const MATRIX: [[u8; 4]; 3] = [[7u8; 4]; 3]
const COPY: [[u8; 4]; 3] = if true { MATRIX } else { MATRIX }
const VALUE: u8 = COPY[2usize][3usize]
fn main(): i32 { (VALUE as i32) - 7 }
