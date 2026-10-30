// expect-error: name 6:39 unresolved

type Box<T> { value:T }
type Owned { value:i32 }
impl<T:Copy> Box<T> { fn answer():i32{42} }
fn main():i32{let value=Box(Owned(0));value.answer()}
