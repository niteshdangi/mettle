// expect-error: ownership 2:45 requires Copy
fn wrong<T,const N:i32>(value:take T):[T;N]{[value;N]}
fn main():i32{0}
