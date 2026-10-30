
type Guard<region r> { value: mut i32 from r; drop { *self.value += 1 } }
fn choose(value: mut i32, flag: bool): Guard {
    loop {
        if flag { break Guard(mut value) }
        break Guard(mut value)
    }
}
fn main() {
    var value = 40
    { let result = choose(value, true); let moved = result }
    let _ = loop { break Guard(mut value) }
    if value == 42 { 0 } else { 1 }
}
