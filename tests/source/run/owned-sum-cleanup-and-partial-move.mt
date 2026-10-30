
type Guard<region r> { log: mut i32 from r; drop { *self.log += 1 } }
enum Container { Held(Guard); Empty }
fn main() {
    var log = 40
    { let value = Container::Held(Guard(mut log)); match take value { Container::Held(guard) => { let moved = guard }, Container::Empty => {} } }
    { let empty = Container::Empty }
    { let value = present(Guard(mut log)); match take value { present(guard) => {}, none => {} } }
    if log == 42 { 0 } else { 1 }
}
