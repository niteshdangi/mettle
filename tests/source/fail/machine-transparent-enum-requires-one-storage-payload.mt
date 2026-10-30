// expect-error: attribute 2:22 object layout cannot be established for this representation
@layout(transparent) enum Invalid { Only(i32,i32) }
fn main() { 0 }
