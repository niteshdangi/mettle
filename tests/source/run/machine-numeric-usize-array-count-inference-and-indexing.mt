
fn repeated<const N: usize>(): [i32;N] { [21;N] }
fn sum<const N: usize>(values: read [i32;N]): i32 {
    var result = 0
    for value in values { result += value }
    result
}
fn at<const N: usize>(values: read [i32;N],index: usize): i32 { values[index] }
fn from_slice(values: read [i32],index: usize): i32 { values[index] }
fn main() {
    let values = repeated<2usize>()
    let index = 1usize
    let slice: read [i32] = read values
    if sum(values) == 42 && at(values,index) == 21 &&
       from_slice(slice,index) == 21 && slice[1usize] == 21 &&
       values[0usize] == 21 { 0 } else { 1 }
}
