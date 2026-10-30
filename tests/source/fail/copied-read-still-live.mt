// expect-error: ownership 2:56 live read loan
fn main() { var x = 1; let v = read x; let copied = v; x = 2; *copied }
