// expect-error: type 2:1 unknown interface bound
fn wrong<T:Missing>(value:T):Unit{()}
fn main():i32{0}
