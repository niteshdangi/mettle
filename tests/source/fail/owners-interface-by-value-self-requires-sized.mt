// expect-error: type 3:26 interface's 'Self' is unsized unless declared 'interface Name: Sized'

interface Consume { take fn consume(): i32; }
fn main() { 0 }
