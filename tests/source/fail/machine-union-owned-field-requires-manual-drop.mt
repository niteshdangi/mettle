// expect-error: type 3:1 union fields requiring destruction must use ManuallyDrop storage
type Owned { drop {} }
union Wrong { value: Owned; bits: usize }
fn main() { 0 }
