// expect-error: ownership 3:34 destructor directly
type Guard { drop {} }
fn main() { var guard = Guard(); Guard.drop(guard); 0 }
