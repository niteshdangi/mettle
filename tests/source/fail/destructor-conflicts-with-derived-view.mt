// expect-error: ownership 7:63 live read loan

type Guard<region r> { value: mut i32 from r; drop { *self.value = 0 } }
fn main() {
    var value = 42
    let child: read i32
    { let guard = Guard(mut value); child = read *guard.value }
    *child
}
