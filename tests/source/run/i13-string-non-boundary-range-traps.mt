// expect-exit: trap
import alloc.string

fn main(): i32 {
    var value = string.from_text("a\u{e9}")
    value.replace_range(2usize, 2usize, "")
    0
}
