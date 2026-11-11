copy type Dimensions { pub width: usize }
extend Dimensions { const VALUE: Dimensions = Dimensions(2usize) }
const fn width(): usize { Dimensions.VALUE.width }
const WIDTH: usize = width()
fn main(): i32 {
    let values: [u8;Dimensions.VALUE.width] = [3u8;WIDTH]
    if values[1] == 3u8 && WIDTH == 2usize { 0 } else { 1 }
}
