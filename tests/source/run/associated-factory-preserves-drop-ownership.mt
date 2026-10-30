
alias OwnedGuard = Guard
type Guard<region r> {
    counter: mut i32 from r
    static fn make(counter: mut i32): Guard { Guard(mut counter) }
    drop { *self.counter += 1 }
}
fn main() {
    var counter = 40
    {
        let first = OwnedGuard::make(counter)
        let moved = first
    }
    { let second = Guard::make(counter) }
    if counter == 42 { 0 } else { 1 }
}
