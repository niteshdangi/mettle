// expect-error: type 3:1 unconstrained implementation parameter
type Plain{}
impl<const N:i32> Plain{fn answer():i32{N}}
fn main():i32{0}
