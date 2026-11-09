// expect-error: ownership 4:33 live exclusive loan
type C { value: i32; fn get() { self.value } }
fn add(mut c: C,n: i32) { c.value += n }
fn main() { var c = C(1); add(c,c.get()); 0 }
