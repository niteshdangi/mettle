// expect-error: type 2:60 invalid primitive
unsafe extern "C" fn callback(count: i32,args: ...): i32 { args.arg<fn(): i32>(); 0 }; fn main() { 0 }
