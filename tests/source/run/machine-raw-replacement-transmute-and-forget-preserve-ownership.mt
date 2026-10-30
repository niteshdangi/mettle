
type Counted {
    counter: ptr<mut i32>; amount: i32
    drop { unsafe { *self.counter += self.amount } }
}
fn main() {
    var count = 0
    let counter = core.ptr.from_mut(count)
    {
        var value = Counted(counter,10)
        {
            let old = unsafe {
                core.ptr.replace(core.ptr.from_mut(value),Counted(counter,32))
            }
        }
        core.mem.forget(Counted(counter,1000))
    }
    let float: f32 = unsafe { core.mem.transmute(0x3f800000u32) }
    let bits = unsafe { core.mem.transmute<u32>(float) }
    let zero: u64 = unsafe { core.mem.zeroed() }
    if count == 42 && float == 1.0f32 && bits == 0x3f800000u32 &&
       zero == 0u64 { 0 } else { 1 }
}
