// expect-error: ownership 2:72 may have been moved
unsafe extern "C" fn callback(count: i32,args: ...): i32 { args.end(); args.arg<i32>() }; fn main() { 0 }
