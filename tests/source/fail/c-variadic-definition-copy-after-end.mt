// expect-error: ownership 2:85 may have been moved
unsafe extern "C" fn callback(count: i32,args: ...): i32 { args.end(); let copied = args.copy(); 0 }; fn main() { 0 }
