// profiles: debug release
// A formatted message (the `Arguments` of a format call) renders through Display and
// Debug, clones into a copyable view, and converts to text and to an owner.
import alloc.string.{String, ToString}
import core.borrow.ToOwned
import core.clone.Clone
import core.fmt
import core.fmt.{Debug, Message}

fn debug_text<T: Debug>(read value: T): String {
    var output = String("")
    var formatter = fmt.formatter(mut output, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => {}
    }
    output
}

fn inspect(message: format Message): i32 {
    if message.to_string().as_text() != "n=7 s=ok" { return 1 }
    let cloned = message.clone()
    let copied = cloned
    if copied.to_string().as_text() != "n=7 s=ok" || cloned.to_string().as_text() != "n=7 s=ok" { return 2 }
    let owned = message.to_owned()
    if owned.to_string().as_text() != "n=7 s=ok" { return 3 }
    if debug_text(cloned).as_text() != "n=7 s=ok" { return 4 }
    0
}

fn literal_only(message: format Message): i32 {
    match message.as_str() {
        present(text) => { if text != "plain" { return 11 } },
        none => { return 12 }
    }
    if message.to_string().as_text() != "plain" { return 13 }
    0
}

fn main(): i32 {
    let number = 7
    let state = "ok"
    let first = inspect(f"n={number} s={state}")
    if first != 0 { return first }
    literal_only(f"plain")
}
