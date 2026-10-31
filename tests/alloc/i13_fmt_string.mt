import alloc.fmt
import alloc.string.String

fn main(): i32 {
    let n = 42
    let word = "hi"
    let owned = alloc.string.from_text("owned")
    let s = fmt.string(f"{word}-{n}-{owned}")
    if s.as_text() != "hi-42-owned" { return 1 }
    let plain = fmt.string("literal")
    if plain.as_text() != "literal" { return 2 }
    let empty = fmt.string("")
    if empty.len() != 0usize { return 3 }
    0
}
