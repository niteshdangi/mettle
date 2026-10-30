// expect-error: ownership 2:47 live read loan
fn main() { let view = loop { let owned = 42; break read owned }; *view }
