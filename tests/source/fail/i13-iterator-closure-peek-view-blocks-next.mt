// expect-error: ownership 8:13 live exclusive loan
import core.iter
import core.iter.Iterator

fn main(): i32 {
    var items = iter.range(0, 2).peekable()
    let held = items.peek_mut()
    let y = items.next()
    match take held { present(value) => { *value += 1 }, none => {} }
    let _ = y
    0
}
