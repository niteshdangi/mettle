
type Guard {
    counter: ptr<mut i32>; amount: i32
    drop { unsafe { *self.counter += self.amount } }
}
fn main() {
    var count = 0
    let pointer = core.ptr.from_mut(count)
    {
        var storage = core.mem.MaybeUninit<Guard>.uninit()
        let previous = storage.write(Guard(pointer,100))
        let current = storage.write(Guard(pointer,1))
        current.amount = 2
        let value = unsafe { storage.assume_init() }
    }
    if count == 2 { 0 } else { 1 }
}
