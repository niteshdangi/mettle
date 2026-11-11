// stdin: mettle-macro 1.0\n
fn main(): i32 {
    match take capture std.macros.read_invocation() {
        failure(error) => if error.kind().is(std.io.ErrorKind.InvalidData) { 0 } else { 1 },
        success(_) => 2
    }
}
