// expect-error: ownership 8:5 live read loan

copy type Pair { first: i32; second: i32 }
fn main() {
    var value = Pair(20,22)
    let storage = core.mem.MaybeUninit.new(read value)
    let reference = unsafe { storage.assume_init() }
    value.first = 40
    reference.first + reference.second
}
