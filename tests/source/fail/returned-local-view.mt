// expect-error: ownership 2:65 returned view escapes
fn bad(source: read i32): read i32 from source { let owned = 1; read owned }
fn main() { 0 }
