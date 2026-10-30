// expect-error: type 3:18 excess explicit generic arguments
fn id<T>(x: take T): T { x }
fn main(): i32 { id::<i32, i32>(1) }
