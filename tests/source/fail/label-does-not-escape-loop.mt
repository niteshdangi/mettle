// expect-error: name 2:41 unknown loop label 'done'
fn main() { label done: loop { break }; break label done; 0 }
