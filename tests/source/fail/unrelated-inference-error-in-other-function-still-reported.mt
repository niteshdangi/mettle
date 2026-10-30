// expect-error-count: 2
// expect-error: type 4:15 cannot infer local type; add ': Type'
fn a(): i32 { let x = nosuch(); 0 }
fn b(): i32 { let y = none; 0 }
fn main(): i32 { 0 }
