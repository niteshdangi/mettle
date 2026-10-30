// expect-error: type 6:35 Copy

interface Family { type Item: Copy; }
type Owned { value: i32 }
type Number {}
extend Number implements Family { type Item = Owned }
fn main() { 0 }
