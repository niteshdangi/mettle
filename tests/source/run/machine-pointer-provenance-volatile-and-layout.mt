
fn main() {
    var value = 40i64
    let pointer = core.ptr.from_mut(value)
    let same = pointer.with_addr(pointer.addr()).wrapping_add(0)
    unsafe {
        pointer.write_volatile(41)
        same.write(same.read_volatile() + 1)
    }
    let null: ptr<read i64> = core.ptr.null()
    if value == 42i64 && pointer == same && null.is_null() &&
       core.mem.size_of<u128>() == 16usize &&
       core.mem.align_of<i64>() == 8usize &&
       !core.mem.needs_drop<i64>() { 0 } else { 1 }
}
