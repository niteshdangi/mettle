// expect-error: ownership 10:5 access or storage lifetime conflicts
type Borrowed<region r> { value: read i32 from r }
type Holder { value: i32 }
extend Holder {
    fn snapshot(): Borrowed<region self> { Borrowed(read self.value) }
}
fn main(): i32 {
    var holder = Holder(7)
    let borrowed = holder.snapshot()
    holder.value = 9
    if *borrowed.value != 7 { return 1 }
    0
}
