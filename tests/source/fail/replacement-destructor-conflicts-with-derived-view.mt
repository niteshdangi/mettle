// expect-error: ownership 9:5 live read loan

type Guard<region r> { value: mut i32 from r; drop { *self.value = 0 } }
fn main() {
    var first = 42
    var second = 0
    var guard = Guard(mut first)
    let child = read *guard.value
    guard = Guard(mut second)
    *child
}
