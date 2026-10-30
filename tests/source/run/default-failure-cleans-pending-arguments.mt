
type Guard<region r> { count: mut i32 from r; drop { *self.count += 1 } }
fn fail(): i32 throws i32 { throw 7 }
fn consume(value: take Guard, answer: i32 = try fail()): i32 throws i32 { answer }
fn main() {
    var drops = 0
    let _ = capture consume(Guard(mut drops))
    if drops == 1 { 0 } else { 1 }
}
