// expect-error: name 2:1 unresolved, inaccessible, ambiguous or cyclic import 'core::num::IntegerBoundsSealed'
import core.num.IntegerBoundsSealed

copy type ForgedInteger { value: i8 }

extend ForgedInteger implements IntegerBoundsSealed {}

fn main(): i32 { 0 }
