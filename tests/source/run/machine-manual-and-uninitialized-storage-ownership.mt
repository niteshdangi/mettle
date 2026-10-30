
type Guard {
    counter: ptr<mut i32>; amount: i32
    drop { unsafe { *self.counter += self.amount } }
}
fn main() {
    var count = 0
    let pointer = core.ptr.from_mut(count)
    { let value = core.mem.ManuallyDrop.new(Guard(pointer,10)) }
    if count != 0 { return 1 }
    {
        let value = core.mem.ManuallyDrop.new(Guard(pointer,1))
        let guard = value.into_inner()
    }
    { let value = core.mem.MaybeUninit.new(Guard(pointer,10)) }
    if count != 1 { return 2 }
    {
        let value = core.mem.MaybeUninit.new(Guard(pointer,2))
        let guard = unsafe { value.assume_init() }
    }
    {
        let cell = core.cell.UnsafeCell.new(Guard(pointer,3))
    }
    if count == 6 { 0 } else { 3 }
}
