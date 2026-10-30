// expect-error: name 2:60 unknown field
unsafe extern "C" fn callback(count: i32,args: ...): i32 { args.0; 0 }; fn main() { 0 }
