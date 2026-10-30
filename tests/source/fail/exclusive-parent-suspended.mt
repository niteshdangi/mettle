// expect-error: ownership 2:59 live exclusive loan
fn main() { var x = 1; let p = mut x; let child = mut *p; *p = 2; *child }
