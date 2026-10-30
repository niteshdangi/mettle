// expect-error: attribute 2:23 duplicate singleton
@export_name("first") @export_name("second")
extern "C" fn operation(): i32 { 42 }
fn main() { 0 }
