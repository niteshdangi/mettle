
type Guard<region r> {
    log: mut i32 from r
    drop { *self.log += 1 }
}
fn inspect(guard: read Guard): Unit { let _ = read guard }
fn consume(guard: take Guard): Unit { let _ = read guard }
fn main(): i32 {
    var repeated_log = 0
    var once_log = 0
    var uncalled_log = 0
    {
        let repeated_guard = Guard(mut repeated_log)
        let repeated = take fn(): Unit { inspect(repeated_guard) }
        repeated()
        repeated()
        let once_guard = Guard(mut once_log)
        let once = take fn(): Unit { consume(once_guard) }
        once()
        let uncalled_guard = Guard(mut uncalled_log)
        let uncalled = take fn(): Unit { inspect(uncalled_guard) }
    }
    if repeated_log == 1 && once_log == 1 &&
       uncalled_log == 1 { 0 } else { 1 }
}
