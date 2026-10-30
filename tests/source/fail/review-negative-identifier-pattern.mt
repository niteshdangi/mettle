// expect-error: parse 2:30 expected an integer literal after '-'
fn f(x:i32):i32 { match x { -x => 1, _ => 0 } }
fn main(){0}
