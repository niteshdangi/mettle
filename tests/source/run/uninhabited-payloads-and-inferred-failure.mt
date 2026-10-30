
enum Empty {}
copy enum Result { Impossible(Never); Value(i32) }
fn impossible(value: Empty): i32 { match value {} }
fn fail() throws i32 { throw 7 }
fn main() {
    let failed = capture fail()
    let error = match failed { failure(error) => error }
    let value = match Result.Value(42) { Result.Value(value) => value }
    if error == 7 && value == 42 { 0 } else { 1 }
}
