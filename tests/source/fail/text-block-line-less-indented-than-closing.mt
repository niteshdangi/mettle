// expect-error-count: 1
// expect-error: lex 4:13 text block line is indented less than its closing """
fn main(): i32 {
    let a = """
      abc
        """
    0
}
