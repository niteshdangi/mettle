// expect-error: type 3:1 cannot infer recursive result
fn f() { g() }
fn g() { f() }
fn main(): i32 { f() }
