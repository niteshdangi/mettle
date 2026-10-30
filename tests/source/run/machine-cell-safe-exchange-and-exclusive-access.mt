
fn main() {
    let first = core::cell::Cell::new(1)
    let second = core::cell::Cell::new(42)
    first.swap(second)
    let old = first.replace(40)
    first.set(first.get() + 2)
    var third = core::cell::Cell::new(0)
    *third.get_mut() = second.into_inner()
    if old == 42 && first.get() == 42 && third.into_inner() == 1 { 0 } else { 1 }
}
