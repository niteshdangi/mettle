// expect-error: type 8:1 overlapping implementations

interface A {}
interface B {}
interface Code { fn code():i32; }
type Box<T> { value:T }
extend<T:A> Box<T> implements Code { fn code():i32{1} }
extend<T:B> Box<T> implements Code { fn code():i32{2} }
fn main():i32{0}
