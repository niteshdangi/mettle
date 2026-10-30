
fn length<T>(values: read [T]): usize { values.len() }
fn identity(values: read [i32]): read [i32] from values { read values }
fn counted(values: read [i32], count: mut i32): read [i32] from values {
    count += 1
    read values
}
fn main() {
    var values = [20, 22]
    var count = 0
    let empty: [i32; 0] = []
    let zero: read [i32] = read empty
    let slice: mut [i32] = mut values
    let n = counted(slice, count).len()
    slice[0] += 1
    if length<i32>(slice) == 2usize && identity(slice).len() == 2usize &&
       zero.len() == 0usize && n == 2usize && count == 1 &&
       slice[0] == 21 { 0 } else { 1 }
}
