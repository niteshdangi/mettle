
type Guard<region r> {
    log: mut i32 from r
    drop { *self.log += 1 }
}
fn move_out<region r>(mut log: i32 from r): Guard<region r> { Guard(mut log) }
fn consume<region r>(take value: Guard<region r>) { let other = value }
fn main() {
    var log = 40
    consume(move_out(log))
    if log == 41 { 0 } else { 1 }
}
