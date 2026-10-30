// expect-error: ownership 3:35 live exclusive loan
type C { value: i32; mut fn add(n: i32) { self.value += n } }
fn main() { var c = C(1); c.add({ c.value = 2; 1 }); 0 }
