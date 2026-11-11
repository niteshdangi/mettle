// expect-error: type 6:1 overlapping implementations cannot be selected by order
interface Marker {}
type Holder<F> { value: F }
extend<T> Holder<fn(read T): T> implements Marker {}

extend Holder<fn(read i32): i32> implements Marker {}
fn main(): i32 { 0 }
