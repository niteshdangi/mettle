// expect-error: type 2:56 expected bool, found i32
fn choose(flag: bool) { loop { if flag { break true }; break 42 } }
fn main() { 0 }
