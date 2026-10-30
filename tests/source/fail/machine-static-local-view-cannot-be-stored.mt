// expect-error: region 2:112 view region or invariant payload does not satisfy its declared relationship
static VALUE: i32 = 1; static mut VIEW: read i32 from static = read VALUE;fn main() { let value = 42; unsafe { VIEW = read value }; 0 }
