// expect-error: type 3:1 not Copy
type Owner { x: i32 }
copy type Bad { owner: Owner }
fn main() { 0 }
