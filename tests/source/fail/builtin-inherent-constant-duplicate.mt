// expect-error: name 6:5 duplicate associated constant
extend char {
    const MARK: char = 'a'
}
extend char {
    const MARK: char = 'b'
}
fn main(): i32 { 0 }
