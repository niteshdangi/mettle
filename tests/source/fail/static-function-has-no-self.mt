// expect-error-count: 1
// expect-error: name 3:32 unresolved value 'self'
type Point { static fn bad() { self.value } }
fn main() { 0 }
