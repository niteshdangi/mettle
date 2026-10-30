// expect-error: type 3:1 unconstrained implementation parameter
type Plain{}
extend<T> Plain{fn answer():i32{42}}
fn main():i32{0}
