// expect-error: type 6:1 overlapping implementations

interface Code { fn code(): i32; }
type Box<T> { value:T }
extend<T> Box<T> implements Code where T=i32 { fn code():i32{1} }
extend<U> Box<U> implements Code where U=i32 { fn code():i32{2} }
fn main():i32{0}
