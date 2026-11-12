
fn repeated<const N: usize>(): [i32;N] { [21;N] }
fn sum<const N: usize>(read values: [i32;N]): i32 {
    var result = 0
    for value in values { result += value }
    result
}
fn at<const N: usize>(read values: [i32;N],index: usize): i32 { values[index] }
fn from_slice(read values: [i32],index: usize): i32 { values[index] }
fn main() {
    var values = repeated<2usize>()
    if values[0usize] != 21 || values[1usize] != 21 { return 2 }
    values[1usize] = 23
    let index = 1usize
    let slice: read [i32] = read values
    if sum(values) == 44 && at(values,index) == 23 &&
       from_slice(slice,index) == 23 && slice[1usize] == 23 &&
       values[0usize] == 21 { 0 } else { 1 }
}
