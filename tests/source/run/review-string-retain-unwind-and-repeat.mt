// profiles: debug release
import alloc.string
import std.panic.CatchResult

fn main(): i32 {
    var text = string.from_text("a\u{e9}x\u{1f600}")
    let result = std.panic.catch_panic(fn(): Unit {
        text.retain(fn(c: char): bool {
            if c == 'x' { panic("retain stop") }
            c != 'a'
        })
    })
    match take result {
        CatchResult.Panicked(info) => { if info.message() != "retain stop" { return 1 } },
        CatchResult.Returned(_) => { return 2 }
    }
    if text.as_text() != "\u{e9}x\u{1f600}" { return 3 }
    text.push('!')
    text.retain(fn(c: char): bool { c != 'x' })
    if text.as_text() != "\u{e9}\u{1f600}!" { return 4 }
    if !"".repeat(0xffffffffffffffffusize).is_empty() { return 6 }
    let overflow = std.panic.catch_panic(fn(): Unit {
        let output = "ab".repeat(0x8000000000000000usize)
    })
    match take overflow {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 5 }
    }
    if "\u{e9}".repeat(3usize).as_text() != "\u{e9}\u{e9}\u{e9}" { return 7 }
    0
}
