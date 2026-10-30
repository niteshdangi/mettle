// expect-error: type 3:1 unconstrained implementation parameter
type Plain{}
impl<T> Plain{fn answer():i32{42}}
fn main():i32{0}
