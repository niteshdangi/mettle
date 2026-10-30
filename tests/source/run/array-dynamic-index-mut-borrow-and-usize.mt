
fn bump(value: mut i32) { value = value + 1 }
fn main(): i32 {
    var values = [10, 20, 30]
    var index = 2usize
    bump(mut values[index])
    let offset = 1
    bump(mut values[offset])
    if values[2usize] == 31 && values[1] == 21 && values[0] == 10 { 0 } else { 1 }
}
