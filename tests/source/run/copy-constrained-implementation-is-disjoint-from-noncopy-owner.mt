
interface Code { fn code(): i32; }
type Box<T> { value: T }
type Owned { value: i32 }
impl<T:Copy> Box<T> implements Code { fn code(): i32 { 42 } }
impl Box<Owned> implements Code { fn code(): i32 { self.value.value } }
fn main(): i32 {
    let copied = Box(0)
    let owned = Box(Owned(42))
    if copied.code() == 42 && owned.code() == 42 { 0 } else { 1 }
}
