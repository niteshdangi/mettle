import alloc.boxed
import alloc.string
import core.iter.{collect, once}
import core.text.Text

fn copy_borrowed_part(): boxed.Box<Text> {
    var backing = string.from_text("borrowed")
    let part = backing.as_text()
    let owned: boxed.Box<Text> = collect(once(part))
    backing.push_str(" changed")
    owned
}

fn main(): i32 {
    let owned = copy_borrowed_part()
    if owned.get() != "borrowed" { return 1 }
    0
}
