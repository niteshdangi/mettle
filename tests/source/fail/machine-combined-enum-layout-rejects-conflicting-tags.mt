// expect-error: attribute 2:14 an enum cannot have multiple integer representations
@layout(C,u8,i8) enum Invalid { First }
fn main() { 0 }
