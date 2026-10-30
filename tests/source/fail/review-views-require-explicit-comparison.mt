// expect-error: type 2:34 view comparisons require explicitly comparing
fn main() { let a=1; let b=2; if read a == read b {1} else {0} }
