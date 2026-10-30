
type Plain {}
extend<T> Plain where T = i32 { fn answer(): i32 { 42 } }
extend<const N:i32> Plain where [i32;N] = [i32;42] {
    fn count(): i32 { N }
}
fn main(): i32 {
    let value = Plain()
    if value.answer() == 42 && value.count() == 42 { 0 } else { 1 }
}
