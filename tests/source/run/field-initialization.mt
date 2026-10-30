
copy type Empty {}
type Inner { value: i32 }
type Outer { inner: Inner; tag: Empty }
fn main() {
    let partial: Outer
    partial.inner.value = 42
    let completed: Outer
    completed.inner.value = 42
    completed.tag = Empty()
    let moved = completed
    if partial.inner.value == 42 && moved.inner.value == 42 { 0 } else { 1 }
}
