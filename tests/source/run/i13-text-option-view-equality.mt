// profiles: debug release
// Optional text views compare by contents even when their borrows differ, with the
// operands passed to the comparison as plain values rather than through a view.
fn main(): i32 {
    let source: read Text = "a,b"
    var split = source.split(",")
    let first = split.next()
    if first != present("a") || !(first == present("a")) { return 1 }
    let literal = present("a")
    if first != literal { return 2 }
    if first == present("b") { return 3 }
    let missing: (read Text from static)? = none
    if missing == present("a") || !missing.is_none() { return 4 }
    if split.next() != present("b") { return 5 }
    if split.next().is_present() { return 6 }
    0
}
