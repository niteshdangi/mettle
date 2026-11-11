fn get(read values: [i32; 1], failed: bool): read [i32; 1] from values throws i32 {
    if failed { throw 9 }
    read values
}
fn first(values: read [i32]): i32 { values[0] }
fn main(): i32 {
    let values = [42]
    let result = capture first(get(values, false))
    let error_result = capture first(get(values, true))
    let answer = match result { success(value) => value, failure(_) => 0 }
    let failed = match error_result { success(_) => false, failure(error) => error == 9 }
    if answer == 42 && failed { 0 } else { 1 }
}
