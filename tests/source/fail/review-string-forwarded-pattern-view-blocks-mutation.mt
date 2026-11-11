// expect-error: ownership 7:5 live read loan
import alloc.string.String

fn main(): i32 {
    var value = String("(body)")
    let body = value.strip_circumfix('(', ')')
    value.push('!')
    match body {
        present(text) => { if text != "body" { return 1 } },
        none => { return 2 }
    }
    0
}
