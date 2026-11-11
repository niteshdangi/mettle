fn sequential<const N: i32>(take a: [i32;N], take b: [i32;65]): i32 {
    var total = 0
    for value in take a { total += value }
    for value in take b { total += value }
    total
}

fn nested<const N: i32>(take rows: [[i32;65];N]): i32 {
    var total = 0
    for row in take rows {
        for value in take row { total += value }
    }
    total
}

fn first<const N: i32>(take a: [i32;N], take b: [i32;65]): i32 {
    for value in take a { let _unused = value }
    for value in take b { return value }
    0
}

fn main(): i32 {
    if sequential<1>([1], [1;65]) == 66 &&
       nested<2>([[1;65];2]) == 130 &&
       first<1>([0], [42;65]) == 42 { 0 } else { 1 }
}
