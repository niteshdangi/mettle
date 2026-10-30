// expect-error: signature 2:33 conflicting external
extern "C" { @link_name("same") static ADDRESS: unsafe extern "C" fn(): i32; @link_name("same") unsafe fn imported(): i32; } fn main() { 0 }
