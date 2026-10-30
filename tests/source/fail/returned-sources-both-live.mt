// expect-error: ownership 3:55 live read loan
fn first(a: read i32, b: read i32): read i32 from (a,b) { read a }
fn main() { var a = 1; var b = 2; let v = first(a,b); b = 3; *v }
