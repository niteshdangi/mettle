// expect-error: type 2:43 enum discriminant is outside its representation
@layout(u8) copy enum Byte { First = 255; Overflow }
fn main() { 0 }
