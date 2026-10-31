import alloc.string
import core.iter.{ExtendItems, FromItems}
import core.convert.From
import core.ops.{Add, AddAssign}

fn main(): i32 {
    var text = string.from_text("ab")
    text.(AddAssign<core.text.Text>).add_assign("\u{e9}")
    if text.as_text() != "ab\u{e9}" { return 1 }
    let joined = text.(Add<core.text.Text>).add("cd")
    if joined.as_text() != "ab\u{e9}cd" || text.as_text() != "ab\u{e9}" { return 2 }

    text.(ExtendItems<char>).extend(['x', '\u{1f600}', 'y'])
    if text.as_text() != "ab\u{e9}x\u{1f600}y" || text.len() != 10usize { return 3 }
    text.(ExtendItems<char>).extend(core.iter.empty<char>())
    if text.len() != 10usize { return 4 }

    let built = string.String.(FromItems<char>).from_iter(['\u{e9}', 'z'])
    if built.as_text() != "\u{e9}z" { return 5 }
    let single = string.String.(From<char>).from('\u{10ffff}')
    if single.len() != 4usize { return 6 }
    0
}
