
copy type Outer { inner: Inner }
copy type Inner { value: i32 }
fn make() { Outer(Inner(42)) }
fn recursive(flag: bool) {
    if flag { make() } else { recursive(true) }
}
fn main() {
    let first = recursive(false)
    let second = first
    let chosen = if false { make() } else { second }
    if first.inner.
        value == 42 && chosen.inner.value == 42 { 0 } else { 1 }
}
