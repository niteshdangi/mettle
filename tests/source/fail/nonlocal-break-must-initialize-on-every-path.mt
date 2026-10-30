// expect-error: type 2:136 may be uninitialized
fn choose(flag: bool) { let answer: i32; label outer: loop { loop { if flag { break label outer }; answer = 42; break label outer } }; answer }
fn main() { choose(false) }
