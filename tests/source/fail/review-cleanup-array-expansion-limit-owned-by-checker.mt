// expect-error: limit 1:1 array length exceeds compiler resource limit
type Owner { drop {} }
fn main() { let value:[[Owner;3000];3000]; 0 }
