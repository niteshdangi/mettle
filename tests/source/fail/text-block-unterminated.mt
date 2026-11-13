// expect-error-count: 1
// expect-error: lex 4:13 unterminated text block
fn main(): i32 {
    let a = """
        abc
    0
}
