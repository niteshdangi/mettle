// expect-error: type 5:34 associated constant value does not match its declared type
interface Origin { const VALUE: Self; }
copy type Point { x: i32 }
copy type Other { y: i32 }
extend Point implements Origin { const VALUE = Other(1) }
fn main(): i32 { 0 }
