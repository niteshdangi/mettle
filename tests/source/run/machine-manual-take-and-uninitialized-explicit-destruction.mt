
type Counted {
    counter: ptr<mut i32>; amount: i32
    drop { unsafe { *self.counter += self.amount } }
}
fn main() {
    var count = 0
    let counter = core::ptr::from_mut(count)
    {
        var storage = core::mem::ManuallyDrop::new(Counted(counter,10))
        let value = unsafe { storage.`take`() }
    }
    {
        var storage = core::mem::MaybeUninit::new(Counted(counter,32))
        unsafe { storage.assume_init_drop() }
    }
    let number = core::mem::MaybeUninit::new(42u64)
    let observed = unsafe { number.assume_init_read() }
    if count == 42 && observed == 42u64 { 0 } else { 1 }
}
