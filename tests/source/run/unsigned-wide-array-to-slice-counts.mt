fn bytes_length(read values: [u8]): usize { values.len() }
fn units_length(read values: [Unit]): usize { values.len() }
fn make_unit(mut calls: i32): Unit { calls += 1 }

fn wide(read values: [u8;2_147_483_648usize]): usize {
    bytes_length(values)
}

fn maximum_zero_sized(read values: [Unit;18_446_744_073_709_551_615usize]): usize {
    units_length(values)
}

fn maximum_cursor(read values: [Unit;18_446_744_073_709_551_615usize]): Unit {
    for value in values { let _unused = value; break }
}

fn main(): i32 {
    let values = [();65]
    var calls = 0
    let maximum: [Unit;18_446_744_073_709_551_615usize] =
        [make_unit(calls);18_446_744_073_709_551_615usize]
    let count = units_length(maximum)
    var iterations = 0
    for value in take maximum {
        let _unused = value
        iterations += 1
        break
    }
    if units_length(values) == 65usize &&
       count == 18_446_744_073_709_551_615usize &&
       calls == 1 && iterations == 1 { 0 } else { 1 }
}
