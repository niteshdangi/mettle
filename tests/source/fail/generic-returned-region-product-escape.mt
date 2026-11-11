// expect-error: region 5:53 declared relationship
interface OwnedType { type Owned; }
extend i32 implements OwnedType { type Owned = i64 }
enum Shared<region r, T: OwnedType> { Value(read T from r); Owned(T.Owned) }
fn bad(read value: i32): Shared<region static, i32> {
    Shared<region value, i32>.Value(read value)
}
fn main(): i32 { 0 }
