import alloc.boxed
import alloc.string.String

fn main(): i32 {
    var source = String("copied \u{1f642}")
    let copied = boxed.copy_text(source.as_text())
    source.clear()
    source.push_str("replaced")
    if copied.get() != "copied \u{1f642}" { return 1 }

    let owned = boxed.from_string(String("moved \u{e9}"))
    if owned.get() != "moved \u{e9}" { return 2 }

    let empty_copy = boxed.copy_text("")
    let empty_owned = boxed.from_string(String(""))
    if empty_copy.get().len() != 0usize || empty_owned.get().len() != 0usize {
        return 3
    }
    0
}
