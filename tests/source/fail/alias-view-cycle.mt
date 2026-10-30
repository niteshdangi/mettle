// expect-error-count: 1
// expect-error: type 3:1 cyclic type alias
alias First = read Second
alias Second = First
fn main() { 0 }
