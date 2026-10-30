
type Guard<region r> {
    value: i32
    log: mut i32 from r
    drop { *self.log = self.value }
}
fn main() {
    var log = 0
    { let guard = Guard(40, mut log) }
    let first = log
    { let view = read Guard(42, mut log); let observed = view.value }
    if first == 40 && log == 42 { 0 } else { 1 }
}
