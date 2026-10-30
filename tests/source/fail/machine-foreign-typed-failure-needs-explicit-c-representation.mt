// expect-error: signature 2:21 native typed failure
extern "C" { unsafe fn operation(): i32 throws i32; }
fn main() { 0 }
