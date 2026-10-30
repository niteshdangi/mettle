// expect-error: type 2:51 expected Unit, found i32
fn choose(flag: bool) { loop { if flag { break }; break 42 } }
fn main() { 0 }
