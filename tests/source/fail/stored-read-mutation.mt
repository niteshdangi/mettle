// expect-error: ownership 2:40 live read loan
fn main() { var x = 1; let v = read x; x = 2; *v }
