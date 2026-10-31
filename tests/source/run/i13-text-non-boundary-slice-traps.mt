// expect-exit: 101
fn main(): i32 {
    let text: read Text = "a\u{e9}"
    let invalid = read text[2..]
    invalid.len() as i32
}
