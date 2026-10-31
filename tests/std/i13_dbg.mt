// expect-stderr: [dbg] 7
// expect-stderr: [dbg] "text"
import std.debug

fn main(): i32 {
    let a = debug.dbg(7)
    if a != 7 { return 1 }
    let b = debug.dbg(alloc.string.from_text("text"))
    if b.as_text() != "text" { return 2 }
    0
}
