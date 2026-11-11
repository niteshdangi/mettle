// expect-error: type 4:1 orphan interface implementation has no local owner
import core.error.Error

extend i32 implements Error {}
fn main(): i32 { 0 }
