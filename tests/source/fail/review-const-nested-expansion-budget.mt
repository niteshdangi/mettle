// expect-error: limit 3:46 aggregate size limit
const MATRIX: [[u8; 65536]; 65536] = [[0u8; 65536]; 65536]
const COPY: [[u8; 65536]; 65536] = if true { MATRIX } else { MATRIX }
fn main(): i32 { 0 }
