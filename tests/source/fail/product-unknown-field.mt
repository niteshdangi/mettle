// expect-error: name 3:13 unknown field 'missing'
copy type P { x: i32 }
fn main() { P(1).missing }
