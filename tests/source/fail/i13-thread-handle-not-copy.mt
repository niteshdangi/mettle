// expect-error: type 3:1 not Copy
import std.thread
copy type Bad { worker: thread.Thread }
fn main(): i32 { 0 }
