// expect-error: name 3:13 unresolved or inaccessible type 'HashMap'
// expect-help: use `Map` for the hash-based key/value collection
fn main() { let values: HashMap<i32, i32> }
