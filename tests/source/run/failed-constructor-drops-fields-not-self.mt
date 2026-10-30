
type Guard<region r> { count: mut i32 from r; drop { *self.count += 1 } }
type Holder<region r> {
    guard: Guard
    count: mut i32 from r
    init(guard: take Guard, count: take (mut i32)) throws i32 {
        self.guard = take guard
        self.count = take count
        throw 7
    }
    drop { *self.count += 100 }
}
fn main() {
    var fields = 0
    var whole = 0
    let _ = capture Holder(Guard(mut fields), mut whole)
    if fields == 1 && whole == 0 { 0 } else { 1 }
}
