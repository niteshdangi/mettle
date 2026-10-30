// expect-exit: trap
import alloc.string.String
fn main(): i32 {
    var s = alloc.string.from_text("h\u{e9}llo")
    s.truncate(2usize)
    0
}
