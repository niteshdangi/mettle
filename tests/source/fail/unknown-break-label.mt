// expect-error: name 2:20 unknown loop label 'missing'
fn main() { loop { break label missing 42 } }
