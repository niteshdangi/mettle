
type Guard<region r> {
    log: mut i32 from r
    drop { *self.log += 1 }
}
fn early(log: mut i32) { let guard = Guard(mut log); return }
fn main() {
    var log = 41
    early(log)
    if log == 42 { 0 } else { 1 }
}
