
type Counted {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter += 1 } }
}
union Storage { owner: core::mem::ManuallyDrop<Counted>; bits: usize }
fn main() {
    var count = 0
    let counter = core::ptr::from_mut(count)
    {
        var storage = Storage(owner: core::mem::ManuallyDrop::new(Counted(counter)))
        unsafe { storage.owner.drop() }
    }
    if count == 1 { 0 } else { 1 }
}
