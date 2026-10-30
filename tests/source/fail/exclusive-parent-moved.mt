// expect-error: ownership 2:72 live read loan
fn main() { var x = 1; let p = mut x; let child = read *p; let moved = p; *child }
