
type Guard<region r> { value: mut i32 from r; drop { *self.value = 0 } }
fn main() {
    var value = 42
    let answer = loop {
        let guard = Guard(mut value)
        break *guard.value
    }
    if answer == 42 && value == 0 { 0 } else { 1 }
}
