// expect-error: type 7:39 interface obligation

interface Lifetime<region r> {}
type StaticOnly {}
extend StaticOnly implements Lifetime<region static> {}
fn accept<T: for<region r> Lifetime<region r>>(value: read T): i32 { 42 }
fn main() { let value = StaticOnly(); accept(value) }
