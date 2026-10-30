// expect-error: type 8:1 overlapping implementations

interface A {}
interface B {}
interface Code { fn code():i32; }
type Box<T> { value:T }
impl<T:A> Box<T> implements Code { fn code():i32{1} }
impl<T:B> Box<T> implements Code { fn code():i32{2} }
fn main():i32{0}
