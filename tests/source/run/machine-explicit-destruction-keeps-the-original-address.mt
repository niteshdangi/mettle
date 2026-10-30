
type Guard {
    counter: ptr<mut i32>; address: ptr<read Guard>
    drop {
        let actual = core.ptr.from_ref(self)
        unsafe {
            if self.address == actual { *self.counter += 1 }
            else { *self.counter += 100 }
        }
    }
}
fn main() {
    var count = 0
    let pointer = core.ptr.from_mut(count)
    var first = core.mem.ManuallyDrop.new(Guard(pointer,core.ptr.null<Guard>()))
    let one = first.get_mut()
    one.address = core.ptr.from_ref(one)
    unsafe { first.drop() }
    var second = core.mem.ManuallyDrop.new(Guard(pointer,core.ptr.null<Guard>()))
    let two = second.get_mut()
    two.address = core.ptr.from_ref(two)
    let address = second.as_mut_ptr()
    unsafe { core.ptr.drop_in_place(address) }
    if count == 2 { 0 } else { 1 }
}
