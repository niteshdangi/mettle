// stdin: mettle-macro 1.12\nname m\ntok word 0 x\n
fn main(): i32 {
    match take capture std.macros.read_invocation() {
        success(request) => {
            if request.name.as_text() != "m" || request.tokens.len() != 1usize { return 1 }
            if request.tokens[0usize].text.as_text() != "x" || request.tokens[0usize].spaced { return 2 }
            0
        },
        failure(_) => 3
    }
}
