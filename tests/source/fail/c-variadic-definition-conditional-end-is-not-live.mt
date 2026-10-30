// expect-error: ownership 2:90 may have been moved
unsafe extern "C" fn callback(count: i32,args: ...): i32 { if count == 0 { args.end() }; args.arg::<i32>() }; fn main() { 0 }
