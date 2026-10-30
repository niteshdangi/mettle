// expect-error: constant 2:1 cycle
static FIRST: i32 = SECOND; static SECOND: i32 = FIRST; fn main() { 0 }
