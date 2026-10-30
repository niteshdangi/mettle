// expect-error: ownership 3:26 destructor directly
type C { drop {} }
fn main() { var c = C(); c.drop(); 0 }
