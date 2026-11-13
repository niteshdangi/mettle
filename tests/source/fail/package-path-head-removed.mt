// expect-error: name 3:1 'package' is not a path head; use the package name `main` instead
module helper { pub fn value(): i32 { 42 } }
import package.helper.value
fn main(): i32 { value() }
