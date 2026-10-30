// expect-error-count: 1
// expect-error: type 6:12 interface bound

interface Family { type Item; }
type Unrelated {}
fn invalid(value: Unrelated.(Family).Item): Unit {}
fn main() { 0 }
