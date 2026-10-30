// expect-error: type 6:33 Copy

interface Family { type Item: Copy; }
type Owned { value: i32 }
type Number {}
impl Number implements Family { type Item = Owned }
fn main() { 0 }
