// expect-error: name 2:12 needs a parent module
pub parent fn answer(): i32 { 42 }
fn main(): i32 { answer() }
