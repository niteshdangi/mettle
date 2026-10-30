// expect-error-count: 1
// expect-error: ownership 4:49 cannot write through a read
alias View = read i32
fn main() { var x = 1; let view: View = read x; *view = 2; 0 }
