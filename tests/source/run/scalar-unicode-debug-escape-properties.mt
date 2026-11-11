// profiles: debug release
import alloc.string
import core.char.Escape
import core.iter.Iterator

fn escaped(take pending: Escape): string.String {
    var iter = pending
    var result = string.new()
    while true {
        match iter.next() {
            present(value) => { result.push(value) },
            none => { break }
        }
    }
    if iter.next().is_present() { core.panic.panic("escape is not fused") }
    result
}

fn main(): i32 {
    if escaped('\u{200b}'.escape_debug()).as_text() != "\\u{200b}" { return 1 }
    if escaped('\u{e000}'.escape_debug()).as_text() != "\\u{e000}" { return 2 }
    if escaped('\u{a0}'.escape_debug()).as_text() != "\\u{a0}" { return 3 }
    if escaped('\u{301}'.escape_debug()).as_text() != "\\u{301}" { return 4 }
    if escaped('\u{ff9e}'.escape_debug()).as_text() != "\u{ff9e}" { return 5 }
    if escaped('\u{ff9f}'.escape_debug()).as_text() != "\u{ff9f}" { return 6 }
    if escaped(' '.escape_debug()).as_text() != " " { return 7 }
    if !'\u{16ea0}'.is_alphabetic() { return 8 }
    0
}
