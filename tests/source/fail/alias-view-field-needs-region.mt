// expect-error: type 3:15 declared region source
alias View = read i32
type Reader { value: View }
fn main() { 0 }
