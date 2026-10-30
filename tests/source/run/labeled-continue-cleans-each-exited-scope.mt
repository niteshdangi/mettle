
type Guard<region r> { count: mut i32 from r; drop { *self.count += 1 } }
copy type Counts { outer: i32; inner: i32 }
fn main() {
    var counts = Counts(0, 0)
    var iterations = 0
    label again: while iterations < 3 {
        let outer = Guard(mut counts.outer)
        iterations += 1
        loop {
            let inner = Guard(mut counts.inner)
            continue label again
        }
    }
    if counts.outer == 3 && counts.inner == 3 { 0 } else { 1 }
}
