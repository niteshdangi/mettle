// expect-error: unsafe 2:53 operation requires an unsafe block or unsafe function
extern "C" fn callback(count: i32,args: ...): i32 { args.arg::<i32>() }; fn main() { 0 }
