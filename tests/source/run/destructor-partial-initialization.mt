
type Guard<region r> {
    value: i32
    log: mut i32 from r
    drop { *self.log += self.value }
}
fn main() {
    var log = 40
    {
        let guard: Guard
        guard.value = 2
        guard.log = mut log
    }
    if log == 42 { 0 } else { 1 }
}
