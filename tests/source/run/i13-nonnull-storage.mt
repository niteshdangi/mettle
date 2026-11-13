// profiles: debug release
import core.ptr.NonNull
import core.cmp.PartialEq

type Counted {
    drops: ptr<mut i32>
    amount: i32
    drop { unsafe { *self.drops += self.amount } }
}

fn main(): i32 {
    var words = [0u32; 3]
    let bytes = NonNull.new(words.as_mut_ptr()).or_panic().cast<u8>()
    let unaligned = unsafe { bytes.add(1usize) }.cast<u32>()
    if unaligned.is_aligned() { return 1 }
    unsafe { unaligned.write_unaligned(0x12345678u32) }
    if unsafe { unaligned.read_unaligned() } != 0x12345678u32 { return 2 }
    if unsafe { bytes.`read`() } != 0u8 ||
        unsafe { bytes.add(5usize).`read`() } != 0u8 {
        return 3
    }
    unsafe { bytes.write_bytes(0xabu8, 12usize) }
    if words != [0xababababu32; 3] { return 4 }
    var slot = 0i32
    let pointer = NonNull.from_mut(mut slot)
    unsafe { pointer.write_volatile(19i32) }
    if unsafe { pointer.read_volatile() } != 19i32 { return 5 }
    var drops = 0i32
    let counter = core.ptr.from_mut(mut drops)
    var storage = core.mem.ManuallyDrop.new(Counted(counter, 1i32))
    let owner = NonNull.new(storage.as_mut_ptr()).or_panic()
    {
        let moved = unsafe { owner.`read`() }
        if moved.amount != 1i32 || drops != 0i32 { return 6 }
    }
    if drops != 1i32 { return 7 }
    unsafe { owner.write(Counted(counter, 2i32)) }
    {
        let previous = unsafe { owner.replace(Counted(counter, 4i32)) }
        if previous.amount != 2i32 || drops != 1i32 { return 8 }
    }
    if drops != 3i32 { return 9 }
    var other = core.mem.ManuallyDrop.new(Counted(counter, 8i32))
    let other_pointer = NonNull.new(other.as_mut_ptr()).or_panic()
    unsafe { owner.swap(other_pointer) }
    unsafe { owner.drop_in_place() }
    if drops != 11i32 { return 10 }
    unsafe { other_pointer.drop_in_place() }
    if drops != 15i32 { return 11 }
    0
}
