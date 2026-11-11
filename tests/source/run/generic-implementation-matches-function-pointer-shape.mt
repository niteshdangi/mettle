interface Marker {}
type Holder<F> { value: F }
extend<T> Holder<fn(read T): T> implements Marker {}
fn identity(read value: i32): i32 { value }
fn marked<T: Marker>(read value: T): i32 { 42 }
fn main(): i32 { marked(Holder(identity)) - 42 }
