
interface Bound { type Output; const COUNT: i32; }
fn inspect<const COUNT: i32,
           T: Bound<type Output=i32, const COUNT=COUNT>>(value: T): Unit { () }
fn inspect_bare<T: Bound<Output=i32, COUNT=42>>(value: T): Unit { () }
fn main(): i32 { 0 }
