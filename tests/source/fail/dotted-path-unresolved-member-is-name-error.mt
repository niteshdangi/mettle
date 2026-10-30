// expect-error: name 2:18 unresolved or inaccessible function 'util.missing'
fn main(): i32 { util.missing(1) }
module util { pub fn known(x: i32): i32 { x } }
