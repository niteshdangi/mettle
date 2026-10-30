// expect-error-count: 1
// expect-error: ownership 3:19 cannot escape
unsafe extern "C" fn callback(count: i32,args: ...) { args }; fn main() { 0 }
