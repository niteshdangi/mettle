// expect-error: ownership 4:44 partially move
type Leaf { value: i32 }
type C { leaf: Leaf; drop {} }
fn main() { let c = C(Leaf(1)); let leaf = c.leaf; 0 }
