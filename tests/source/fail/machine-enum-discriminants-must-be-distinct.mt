// expect-error: type 2:45 duplicate enum discriminant
@layout(i16) copy enum Number { First = -1; Second = -1 }
fn main() { 0 }
