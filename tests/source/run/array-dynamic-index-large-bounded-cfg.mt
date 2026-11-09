
fn get(read v: [i32;3000], i: i32): i32 { v[i] }
fn put(mut v: [i32;3000], i: i32, x: i32) { v[i] = x }
fn main(): i32 {
    var values = [0; 3000]
    var i = 0
    while i < 3000 { put(mut values, i, i * 2); i = i + 1 }
    var sum = 0
    i = 0
    while i < 3000 { sum = sum + get(values, i) - i; i = i + 1 }
    if sum == 4498500 && get(values, 2999) == 5998 { 0 } else { 1 }
}
