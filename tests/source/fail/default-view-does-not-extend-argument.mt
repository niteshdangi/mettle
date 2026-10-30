// expect-error: ownership 3:13 live read loan
fn view(a: i32, b: (read i32) = read a): read i32 from b { b }
fn main() { let result = view(42); *result }
