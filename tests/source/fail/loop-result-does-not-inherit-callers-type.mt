// expect-error: type 3:13 expected i32, found bool
fn answer() { loop { break true } }
fn main() { let answer: i32 = answer(); 0 }
