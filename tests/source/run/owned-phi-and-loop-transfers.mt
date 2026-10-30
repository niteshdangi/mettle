
type Guard<region r> { counter: mut i32 from r; drop { *self.counter += 1 } }
fn route(value: take Guard, flag: bool): Guard from value {
    if flag { value } else { value }
}
fn main() {
    var counter = 0
    var index = 0
    while index < 2 {
        let owned = route(Guard(mut counter), index == 0)
        index += 1
    }
    if counter == 2 { 0 } else { 1 }
}
