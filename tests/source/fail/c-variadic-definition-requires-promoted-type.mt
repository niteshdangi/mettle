// expect-error-count: 1
// expect-error: type 3:60 invalid primitive
unsafe extern "C" fn callback(count: i32,args: ...): i32 { args.arg::<i8>() as i32 }; fn main() { 0 }
