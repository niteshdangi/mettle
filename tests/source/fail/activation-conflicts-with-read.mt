// expect-error: ownership 3:27 live read loan
type C { value: i32; fn view(): read i32 from self { read self.value }; mut fn add(read n: i32) { self.value += n } }
fn main() { var c = C(1); c.add(c.view()); 0 }
